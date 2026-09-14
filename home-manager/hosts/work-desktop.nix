{ ... }:

# Host layer for the `work-desktop` target. Generic knobs only: anything describing the corporate
# network (resolvers, tunnel daemons, app probes) arrives at runtime via ~/.config/box-telemetry/
# {scrape.d,dashboards} from a private repo and is never committed here.
{
  boxTelemetry = {
    enable = true;
    textfileDir = "/home/idhanani/dynamo-traces/metrics/textfile";
    systemdUnits = [ "docker" "ssh" "systemd-resolved" "NetworkManager" "tailscaled" "tailscaled-personal" ];
    probes.dns.system = "127.0.0.53:53";
  };
}
