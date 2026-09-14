{ config, lib, pkgs, ... }:

# Minimal box telemetry: Prometheus + node_exporter + Grafana (one small dashboard), run as a
# docker compose stack whose config files are rendered by Nix. Optional blackbox probes when a host
# declares any. Deliberately small; extend at runtime, not by growing this module:
#   ~/.config/box-telemetry/scrape.d/*.yml    extra Prometheus scrape_configs (mapping with scrape_configs:)
#   ~/.config/box-telemetry/dashboards/*.json extra Grafana dashboards
# Agent-facing usage: agents/skills/box-telemetry/SKILL.md

with lib;

let
  cfg = config.boxTelemetry;
  runtimeDir = "${config.home.homeDirectory}/.config/box-telemetry";
  yaml = pkgs.formats.yaml { };

  probesEnabled = cfg.probes.dns != { } || cfg.probes.https != { };
  blackboxAddr = "localhost:${toString cfg.blackboxPort}";

  probeJob = name: module: targets: {
    job_name = name;
    metrics_path = "/probe";
    scrape_interval = "15s";
    params.module = [ module ];
    static_configs = targets;
    relabel_configs = [
      { source_labels = [ "__address__" ]; target_label = "__param_target"; }
      { source_labels = [ "__param_target" ]; target_label = "instance"; }
      { target_label = "__address__"; replacement = blackboxAddr; }
    ];
  };

  prometheusConfig = yaml.generate "prometheus.yml" {
    global = { scrape_interval = cfg.scrapeInterval; evaluation_interval = cfg.scrapeInterval; };
    scrape_configs = [
      { job_name = "node"; static_configs = [{ targets = [ "localhost:${toString cfg.nodeExporterPort}" ]; }]; }
    ] ++ optionals probesEnabled [
      (probeJob "dns" "dns_a" (mapAttrsToList (n: a: { targets = [ a ]; labels.resolver = n; }) cfg.probes.dns))
      (probeJob "https" "https_up" (mapAttrsToList (n: u: { targets = [ u ]; labels.site = n; }) cfg.probes.https))
    ];
    scrape_config_files = [ "/etc/prometheus/scrape.d/*.yml" ];
  };

  blackboxConfig = yaml.generate "blackbox.yml" {
    modules = {
      http_2xx = { prober = "http"; timeout = "5s"; http = { method = "GET"; valid_status_codes = [ 200 ]; }; };
      https_up = {
        prober = "http"; timeout = "8s";
        http = { method = "GET"; preferred_ip_protocol = "ip4"; follow_redirects = false;
                 valid_status_codes = [ 200 301 302 303 307 308 401 403 ]; };
      };
      auth_required = { prober = "http"; timeout = "5s"; http = { method = "GET"; valid_status_codes = [ 401 ]; }; };
      dns_a = {
        prober = "dns"; timeout = "5s";
        dns = { transport_protocol = "udp"; preferred_ip_protocol = "ip4"; query_name = cfg.probes.dnsQueryName;
                query_type = "A"; valid_rcodes = [ "NOERROR" ];
                validate_answer_rrs.fail_if_none_matches_regexp = [ "\\sA\\s" ]; };
      };
    };
  };

  grafanaProvisioning = pkgs.runCommand "box-grafana-provisioning" { } ''
    mkdir -p $out/datasources $out/dashboards
    cat > $out/datasources/prometheus.yml <<EOF
    apiVersion: 1
    datasources:
      - { name: Prometheus, uid: prometheus, type: prometheus, access: proxy, url: "http://localhost:${toString cfg.prometheusPort}", isDefault: true, editable: false }
    EOF
    cat > $out/dashboards/dashboards.yml <<EOF
    apiVersion: 1
    providers:
      - { name: box, type: file, disableDeletion: false, updateIntervalSeconds: 60, options: { path: /etc/grafana/dashboards/box } }
      - { name: box-extra, type: file, disableDeletion: false, updateIntervalSeconds: 60, options: { path: /etc/grafana/dashboards/extra } }
    EOF
  '';

  dashboards = pkgs.runCommand "box-dashboards" { } ''
    mkdir -p $out && cp ${./box-telemetry/dashboards/box.json} $out/box.json
  '';

  unitRegex = "^(${concatStringsSep "|" cfg.systemdUnits})\\.service$$";

  # Built line-by-line so the indentation survives Nix's indented-string stripping.
  blackboxService = optionalString probesEnabled (concatStringsSep "\n" [
    ""
    "  blackbox-exporter:"
    "    image: prom/blackbox-exporter:latest"
    "    container_name: ${cfg.projectName}-blackbox"
    "    restart: unless-stopped"
    "    network_mode: host"
    "    volumes:"
    "      - ${blackboxConfig}:/etc/blackbox_exporter/config.yml:ro"
    "    command:"
    "      - --config.file=/etc/blackbox_exporter/config.yml"
    "      - --web.listen-address=:${toString cfg.blackboxPort}"
    ""
  ]);

  composeFile = pkgs.writeText "docker-compose.yml" ''
    # Rendered by home-manager (modules/box-telemetry.nix); edit the Nix, not this file.
    name: ${cfg.projectName}
    services:
      node-exporter:
        image: prom/node-exporter:latest
        container_name: ${cfg.projectName}-node-exporter
        restart: unless-stopped
        network_mode: host
        pid: host
    ${optionalString cfg.nodeExporterApparmorUnconfined
      "    security_opt: [apparmor=unconfined]  # Ubuntu docker-default blocks D-Bus; systemd collector needs it"}
        volumes:
          - /proc:/host/proc:ro
          - /sys:/host/sys:ro
          - /:/rootfs:ro
          - /run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro
          - ${cfg.textfileDir}:/textfile:ro
        command:
          - --web.listen-address=:${toString cfg.nodeExporterPort}
          - --path.procfs=/host/proc
          - --path.sysfs=/host/sys
          - --path.rootfs=/rootfs
          - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
          - --collector.textfile.directory=/textfile
          - --collector.systemd
          - --collector.systemd.unit-include=${unitRegex}
          - --collector.network_route
    ${blackboxService}
      prometheus:
        image: prom/prometheus:latest
        container_name: ${cfg.projectName}-prometheus
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

      grafana:
        image: grafana/grafana-oss:latest
        container_name: ${cfg.projectName}-grafana
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
          - ${dashboards}:/etc/grafana/dashboards/box:ro
          - ${runtimeDir}/dashboards:/etc/grafana/dashboards/extra:ro

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
    enable = mkEnableOption "minimal box telemetry stack (Prometheus + node_exporter + Grafana via docker compose)";
    projectName = mkOption { type = types.str; default = "box-telemetry"; description = "compose project; volumes are <project>_prometheus-data / _grafana-data"; };
    prometheusPort = mkOption { type = types.port; default = 9091; };
    grafanaPort = mkOption { type = types.port; default = 3001; };
    nodeExporterPort = mkOption { type = types.port; default = 9100; };
    blackboxPort = mkOption { type = types.port; default = 9116; };
    retention = mkOption { type = types.str; default = "90d"; };
    scrapeInterval = mkOption { type = types.str; default = "30s"; };
    prometheusExtraFlags = mkOption { type = types.listOf types.str; default = [ ]; };
    textfileDir = mkOption { type = types.str; default = "${runtimeDir}/textfile"; description = "node_exporter textfile collector dir"; };
    nodeExporterApparmorUnconfined = mkOption { type = types.bool; default = true; };
    systemdUnits = mkOption {
      type = types.listOf types.str;
      default = [ "docker" "ssh" "systemd-resolved" "NetworkManager" ];
      description = "System-scope units (no .service) whose state is exported. systemd --user units are not visible.";
    };
    probes = {
      dns = mkOption { type = types.attrsOf types.str; default = { }; description = "resolver label -> host:port; each is asked for dnsQueryName. Any entry enables blackbox."; };
      https = mkOption { type = types.attrsOf types.str; default = { }; description = "site label -> URL. Any entry enables blackbox."; };
      dnsQueryName = mkOption { type = types.str; default = "github.com"; };
    };
  };

  config = mkIf cfg.enable {
    assertions = [{ assertion = pkgs.stdenv.isLinux; message = "boxTelemetry: Linux only (host-network docker compose)."; }];

    home.file.".config/box-telemetry/docker-compose.yml".source = composeFile;

    systemd.user.services.box-telemetry = {
      Unit = { Description = "Box telemetry stack (docker compose up -d)"; After = [ "network-online.target" ]; };
      Service = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${composeUp}"; TimeoutStartSec = "5min"; };
      Install.WantedBy = [ "default.target" ];
    };
    # A dirty reboot once left Prometheus down for three days; re-assert every 10 minutes.
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
