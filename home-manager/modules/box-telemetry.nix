{ config, lib, pkgs, ... }:

# Box telemetry: Prometheus + Grafana + node/process/blackbox exporters, run as a docker compose
# stack whose every config file is rendered by Nix. Gives an agent (or you) one place to ask
# "is X up / was DNS down at 20:30 / what is this box doing" instead of poking ss/dig/ps by hand.
#
# Host-private detail (corp resolvers, private probes, app dashboards) never enters this repo:
#   ~/.config/box-telemetry/scrape.d/*.yml   -> extra Prometheus scrape configs, read at runtime
#   ~/.config/box-telemetry/dashboards/*.json -> extra Grafana dashboards, provisioned at runtime
# See agents/skills/box-telemetry/SKILL.md for the query recipe.

with lib;

let
  cfg = config.boxTelemetry;
  runtimeDir = "${config.home.homeDirectory}/.config/box-telemetry";
  yaml = pkgs.formats.yaml { };

  blackboxRelabel = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = "localhost:9115"; }
  ];

  probeJob = name: module: targets: {
    job_name = name;
    metrics_path = "/probe";
    scrape_interval = "15s";
    params.module = [ module ];
    static_configs = targets;
    relabel_configs = blackboxRelabel;
  };

  prometheusConfig = yaml.generate "prometheus.yml" {
    global = { scrape_interval = cfg.scrapeInterval; evaluation_interval = cfg.scrapeInterval; };
    scrape_configs = [
      { job_name = "node"; static_configs = [{ targets = [ "localhost:9100" ]; }]; }
      { job_name = "process"; static_configs = [{ targets = [ "localhost:9256" ]; }]; }
      (probeJob "https" "https_up"
        (mapAttrsToList (site: url: { targets = [ url ]; labels.site = site; }) cfg.probes.https))
      (probeJob "dns" "dns_a"
        (mapAttrsToList (name: addr: { targets = [ addr ]; labels.resolver = name; }) cfg.probes.dnsResolvers))
    ];
    # Host-private jobs live outside the repo and are picked up here.
    scrape_config_files = [ "/etc/prometheus/scrape.d/*.yml" ];
  };

  blackboxConfig = yaml.generate "blackbox.yml" {
    modules = {
      http_2xx = { prober = "http"; timeout = "5s"; http = { method = "GET"; valid_status_codes = [ 200 ]; }; };
      # "Can this box reach the site" -- auth walls and redirects still count as reachable.
      https_up = {
        prober = "http"; timeout = "8s";
        http = { method = "GET"; preferred_ip_protocol = "ip4"; follow_redirects = false;
                 valid_status_codes = [ 200 301 302 303 307 308 401 403 ]; };
      };
      # Passes only when the target demands auth: a "the lock is still on" probe.
      auth_required = { prober = "http"; timeout = "5s"; http = { method = "GET"; valid_status_codes = [ 401 ]; }; };
      # Target = a resolver (host:port); query a public name through it.
      dns_a = {
        prober = "dns"; timeout = "5s";
        dns = { transport_protocol = "udp"; preferred_ip_protocol = "ip4"; query_name = cfg.probes.dnsQueryName;
                query_type = "A"; valid_rcodes = [ "NOERROR" ];
                validate_answer_rrs.fail_if_none_matches_regexp = [ "\\sA\\s" ]; };
      };
    };
  };

  processExporterConfig = yaml.generate "process-exporter.yml" {
    process_names = cfg.extraProcessNames ++ [{ name = "{{.Comm}}"; comm = cfg.processGroups; }];
  };

  grafanaProvisioning = pkgs.runCommand "grafana-provisioning" { } ''
    mkdir -p $out/datasources $out/dashboards
    cat > $out/datasources/prometheus.yml <<EOF
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus
        type: prometheus
        access: proxy
        url: http://localhost:${toString cfg.prometheusPort}
        isDefault: true
        editable: false
    EOF
    cat > $out/dashboards/dashboards.yml <<EOF
    apiVersion: 1
    providers:
      - name: box-telemetry
        type: file
        disableDeletion: false
        updateIntervalSeconds: 60
        options: { path: /etc/grafana/dashboards/generic }
      - name: box-telemetry-extra
        type: file
        disableDeletion: false
        updateIntervalSeconds: 60
        options: { path: /etc/grafana/dashboards/extra }
    EOF
  '';

  genericDashboards = pkgs.runCommand "box-dashboards" { } ''
    mkdir -p $out
    cp ${./box-telemetry/dashboards/box.json} $out/box.json
  '';

  unitRegex = "^(${concatStringsSep "|" cfg.systemdUnits})\\.service$$";

  composeFile = pkgs.writeText "docker-compose.yml" ''
    # Rendered by home-manager (modules/box-telemetry.nix); do not edit by hand.
    # Host network on purpose: single-tenant box, every hop is localhost:<port>.
    name: ${cfg.projectName}
    services:
      node-exporter:
        image: prom/node-exporter:latest
        container_name: node-exporter
        restart: unless-stopped
        network_mode: host
        pid: host
    ${optionalString cfg.nodeExporterApparmorUnconfined
      "    # Ubuntu's docker-default AppArmor profile blocks D-Bus; the systemd collector needs it.\n    security_opt:\n      - apparmor=unconfined"}
        volumes:
          - /proc:/host/proc:ro
          - /sys:/host/sys:ro
          - /:/rootfs:ro
          - /run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro
          - ${cfg.textfileDir}:/textfile:ro
        command:
          - --path.procfs=/host/proc
          - --path.sysfs=/host/sys
          - --path.rootfs=/rootfs
          - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
          - --collector.textfile.directory=/textfile
          - --collector.systemd
          - --collector.systemd.unit-include=${unitRegex}
          - --collector.network_route

      process-exporter:
        image: ncabatoff/process-exporter:latest
        container_name: process-exporter
        restart: unless-stopped
        network_mode: host
        pid: host
        privileged: true
        volumes:
          - /proc:/host/proc:ro
          - ${processExporterConfig}:/config/config.yml:ro
        command:
          - --procfs=/host/proc
          - --config.path=/config/config.yml
          - --web.listen-address=:9256

      blackbox-exporter:
        image: prom/blackbox-exporter:latest
        container_name: blackbox-exporter
        restart: unless-stopped
        network_mode: host
        volumes:
          - ${blackboxConfig}:/etc/blackbox_exporter/config.yml:ro
        command:
          - --config.file=/etc/blackbox_exporter/config.yml

      prometheus:
        image: prom/prometheus:latest
        container_name: prometheus
        restart: unless-stopped
        network_mode: host
        volumes:
          - ${prometheusConfig}:/etc/prometheus/prometheus.yml:ro
          - ${runtimeDir}/scrape.d:/etc/prometheus/scrape.d:ro
          - prometheus-data:/prometheus
        command:
          - --config.file=/etc/prometheus/prometheus.yml
          - --storage.tsdb.path=/prometheus
          - --storage.tsdb.retention.time=${cfg.retention}
          - --web.listen-address=:${toString cfg.prometheusPort}
          - --web.enable-lifecycle
    ${concatMapStringsSep "\n" (f: "      - ${f}") cfg.prometheusExtraFlags}
        depends_on:
          - node-exporter

      grafana:
        image: grafana/grafana-oss:latest
        container_name: grafana
        restart: unless-stopped
        network_mode: host
        environment:
          - GF_SERVER_HTTP_PORT=${toString cfg.grafanaPort}
          - GF_AUTH_ANONYMOUS_ENABLED=true
          - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
          - GF_USERS_ALLOW_SIGN_UP=false
        volumes:
          - grafana-data:/var/lib/grafana
          - ${grafanaProvisioning}:/etc/grafana/provisioning:ro
          - ${genericDashboards}:/etc/grafana/dashboards/generic:ro
          - ${runtimeDir}/dashboards:/etc/grafana/dashboards/extra:ro
        depends_on:
          - prometheus

    volumes:
      prometheus-data:
      grafana-data:
  '';

  composeUp = pkgs.writeShellScript "box-telemetry-up" ''
    set -euo pipefail
    export PATH=/usr/bin:/bin:/usr/local/bin:$PATH
    mkdir -p ${runtimeDir}/scrape.d ${runtimeDir}/dashboards ${cfg.textfileDir}
    exec docker compose -p ${cfg.projectName} -f ${composeFile} up -d --remove-orphans
  '';
in
{
  options.boxTelemetry = {
    enable = mkEnableOption "box telemetry stack (Prometheus, Grafana, node/process/blackbox exporters via docker compose)";

    projectName = mkOption {
      type = types.str; default = "observability";
      description = "docker compose project name; the named volumes are <project>_prometheus-data / _grafana-data.";
    };
    prometheusPort = mkOption { type = types.port; default = 9090; };
    grafanaPort = mkOption { type = types.port; default = 3000; };
    retention = mkOption { type = types.str; default = "90d"; };
    scrapeInterval = mkOption { type = types.str; default = "30s"; };
    prometheusExtraFlags = mkOption { type = types.listOf types.str; default = [ ]; };

    textfileDir = mkOption {
      type = types.str; default = "${runtimeDir}/textfile";
      description = "node_exporter textfile-collector directory (drop *.prom files here).";
    };
    nodeExporterApparmorUnconfined = mkOption { type = types.bool; default = true; };

    systemdUnits = mkOption {
      type = types.listOf types.str;
      default = [ "docker" "ssh" "systemd-resolved" "NetworkManager" ];
      description = "System-scope units (no .service suffix) to export state for. systemd --user units are not visible; watch their processes instead.";
    };
    processGroups = mkOption {
      type = types.listOf types.str;
      default = [ "dockerd" "sshd" "prometheus" "grafana" "node_exporter" "codex" "claude" ];
      description = "Process comm names (15-char kernel truncation applies) to track presence/CPU/RSS for.";
    };
    extraProcessNames = mkOption {
      type = types.listOf types.attrs; default = [ ];
      description = "Raw process-exporter process_names entries; matched before the comm list (e.g. split two daemons with the same comm by cmdline).";
    };

    probes = {
      https = mkOption {
        type = types.attrsOf types.str;
        default = { github = "https://github.com"; anthropic-api = "https://api.anthropic.com/v1/models"; };
        description = "site label -> URL, probed end-to-end via the system resolver.";
      };
      dnsResolvers = mkOption {
        type = types.attrsOf types.str;
        default = { system = "127.0.0.53:53"; };
        description = "resolver label -> host:port. Each is asked for probes.dnsQueryName separately, so a dead VPN/ZTNA resolver shows up as such.";
      };
      dnsQueryName = mkOption { type = types.str; default = "github.com"; };
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = pkgs.stdenv.isLinux;
      message = "boxTelemetry runs a host-network docker compose stack; Linux only.";
    }];

    home.file.".config/box-telemetry/docker-compose.yml".source = composeFile;
    home.file.".config/box-telemetry/README.md".text = ''
      Rendered by home-manager (modules/box-telemetry.nix). Grafana :${toString cfg.grafanaPort}, Prometheus :${toString cfg.prometheusPort}.
      Host-private additions go here (read at runtime, never in the repo):
        scrape.d/*.yml   extra Prometheus scrape_configs (then: curl -X POST localhost:${toString cfg.prometheusPort}/-/reload)
        dashboards/*.json extra Grafana dashboards (picked up within 60 s)
      Manage: systemctl --user {status,start} box-telemetry.service ; docker compose -p ${cfg.projectName} ps
    '';

    systemd.user.services.box-telemetry = {
      Unit = { Description = "Box telemetry stack (docker compose up -d)"; After = [ "network-online.target" ]; };
      Service = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${composeUp}"; TimeoutStartSec = "5min"; };
      Install.WantedBy = [ "default.target" ];
    };
    # Re-asserts the stack every 10 minutes: a dirty reboot once left Prometheus down for three days.
    systemd.user.timers.box-telemetry = {
      Unit.Description = "Keep the box telemetry stack running";
      Timer = { OnBootSec = "2min"; OnUnitActiveSec = "10min"; Unit = "box-telemetry.service"; };
      Install.WantedBy = [ "timers.target" ];
    };

    home.activation.boxTelemetryUp = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
        run systemctl --user restart box-telemetry.service || echo "box-telemetry: start failed (is docker running?)"
      fi
    '';
  };
}
