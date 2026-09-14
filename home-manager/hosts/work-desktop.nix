{ ... }:

# Host layer for the `work-desktop` target. Only generic knobs live here; anything that describes
# the corporate network (resolvers, tunnel daemons, app probes) is delivered at runtime through
# ~/.config/box-telemetry/{scrape.d,dashboards} by a private repo, never committed here.
{
  boxTelemetry = {
    enable = true;
    textfileDir = "/home/idhanani/dynamo-traces/metrics/textfile";
    # An app on this box pushes OTel metrics (DELTA temporality) straight into Prometheus.
    prometheusExtraFlags = [ "--web.enable-otlp-receiver" "--enable-feature=otlp-deltatocumulative" ];
    systemdUnits = [ "docker" "ssh" "systemd-resolved" "NetworkManager" "tailscaled" "tailscaled-personal" ];
    processGroups = [
      "dockerd" "sshd" "prometheus" "grafana" "node_exporter" "blackbox_export" "process-exporte"
      "codex" "claude" "node" "caddy" "cortexd" "agent-loadgen" "Xorg" "vncserver-x11-c"
      "systemd-resolve" "NetworkManager" "tailscaled"
    ];
    # Two tailscaled daemons share a comm; tell them apart by the personal instance's socket path.
    extraProcessNames = [
      { name = "tailscaled-personal"; cmdline = [ "--socket=/run/tailscale-personal/" ]; }
    ];
    probes.https = {
      github = "https://github.com";
      anthropic-api = "https://api.anthropic.com/v1/models";
      claude = "https://claude.ai";
    };
  };
}
