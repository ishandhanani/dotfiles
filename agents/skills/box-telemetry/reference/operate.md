# Operating and extending the stack

Defined in `home-manager/modules/box-telemetry.nix`, enabled per host in `home-manager/hosts/<target>.nix`.
Runs `docker compose -p box-telemetry` from a Nix-rendered compose file; every config is a store path
bind-mounted into the containers, so `home-manager switch` recreates only containers whose config changed.
`box-telemetry.service` (oneshot) starts it; a 10-minute timer re-asserts it after dirty reboots.

- Status: `systemctl --user status box-telemetry.service`, `docker compose -p box-telemetry ps`, `docker logs box-telemetry-prometheus`.
- Add a private scrape job (no repo change): drop a file in `~/.config/box-telemetry/scrape.d/` shaped as
  `scrape_configs: [ ... ]` (a bare list crash-loops Prometheus), then `curl -X POST localhost:9091/-/reload`.
  Blackbox modules available when the host declares any probe: `http_2xx`, `https_up`, `auth_required`, `dns_a`
  (relabel `__address__` -> `__param_target`, `__address__` -> `localhost:9116`).
- Add a private dashboard: JSON into `~/.config/box-telemetry/dashboards/` (copies, not symlinks -- the
  container cannot follow links outside the mount); provisioned within 60 s. Check every panel query returns data.
- Generic knobs (units, probes, ports, textfile dir) are Nix options in the host file. Keep corp-specific
  values out of the public repo.
- History lives in the named volumes `box-telemetry_prometheus-data` / `_grafana-data`; never `compose down -v`.

Pitfalls seen: node_exporter's systemd collector needs `apparmor=unconfined` on Ubuntu (D-Bus); a `pkill -f`
pattern that appears in your own command line kills your shell; a second stack on the same host must not share
`:9100`/`:9115`; the box cannot reach its own userspace-Tailscale IP -- test from a peer.
