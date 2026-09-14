---
name: box-telemetry
description: Answer "is X up / what is this box doing / was DNS or the tunnel broken at 20:30" from the box's own Prometheus (node, process, blackbox probes) instead of poking ss/dig/ps by hand. Use whenever a question is about a machine's processes, services, network, DNS, tunnels, disk or reachability and that machine runs the dotfiles boxTelemetry stack.
---

# Box telemetry

Boxes with `boxTelemetry.enable = true` (home-manager, `modules/box-telemetry.nix`) run Prometheus `:9090` and
Grafana `:3000` (anonymous viewer) plus node_exporter, process-exporter and blackbox-exporter, all scraped with
history (90 d default). **Query first, poke second**: a query answers "since when" and "how often", a shell
command only answers "now".

## Query recipe

```bash
# instant (local or over ssh)
curl -s --data-urlencode 'query=<promql>' localhost:9090/api/v1/query | jq '.data.result[] | [.metric, .value[1]]'
# history: 5-min steps over a window
curl -s --data-urlencode 'query=<promql>' --data-urlencode 'start=2026-09-13T20:00:00Z' \
     --data-urlencode 'end=2026-09-13T21:00:00Z' --data-urlencode 'step=300' localhost:9090/api/v1/query_range
# what is being scraped and whether it works
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | [.labels.job, .health, .lastError]'
```

Over SSH: `ssh <box> "curl -s --data-urlencode 'query=...' localhost:9090/api/v1/query"`. Remember this
harness rewrites bare `ssh`/`rm`; use `/usr/bin/ssh` when scripting.

## Metric catalogue

| Question | Query |
|---|---|
| Does public DNS work, per resolver? | `probe_success{job=~"dns.*"}` (`resolver` label; latency `probe_duration_seconds`) |
| Can the box reach site S? | `probe_success{job="https",site="S"}`, `probe_http_status_code`, `probe_duration_seconds` |
| Is an auth lock still on? | `probe_success{job=<auth_required job>}` (module passes only on HTTP 401) |
| Is unit U running? (system scope) | `node_systemd_unit_state{name="U.service",state="active"}` -- `systemd --user` units are invisible; use processes |
| Is process P running / how many? | `namedprocess_namegroup_num_procs{groupname="P"}` (groups = `boxTelemetry.processGroups` / `extraProcessNames`) |
| Process CPU / RSS | `rate(namedprocess_namegroup_cpu_seconds_total{groupname="P"}[2m])`, `namedprocess_namegroup_memory_bytes{memtype="resident"}` |
| Interface traffic | `rate(node_network_receive_bytes_total{device="D"}[1m])` / `..._transmit_...` |
| Is route R installed / on which device? | `node_network_route_info{dest="R"}` (labels `device`, `dest`, `proto`); `count by (device) (node_network_route_info)` |
| Tunnel up? | do **not** trust `node_network_up`/carrier for tun devices (always "unknown"); use its routes (`node_network_route_info{device="tun0"}`) or a probe through it |
| Disk / memory / CPU | `node_filesystem_avail_bytes{mountpoint="/"}`, `node_memory_MemAvailable_bytes`, `rate(node_cpu_seconds_total{mode="idle"}[5m])` |
| Custom gauges from cron scripts | anything written as `*.prom` into `boxTelemetry.textfileDir` |

Timeline of an incident: run the relevant query with `query_range` over the window and read where `probe_success`
or `node_systemd_unit_state` flipped. Grafana: `http://<box>:3000/d/box-telemetry` (generic) plus any extra
dashboards provisioned from `~/.config/box-telemetry/dashboards/`.

## Extending on a box (runtime, no repo change)

- Extra scrape jobs: drop a YAML list of `scrape_configs` entries into `~/.config/box-telemetry/scrape.d/<name>.yml`
  (blackbox jobs: `metrics_path: /probe`, `params.module`, relabel `__address__` -> `__param_target`,
  `__address__` -> `localhost:9115`; modules available: `http_2xx`, `https_up`, `auth_required`, `dns_a`),
  then `curl -X POST localhost:9090/-/reload`.
- Extra dashboards: JSON into `~/.config/box-telemetry/dashboards/`; Grafana picks it up within 60 s.
  Verify every panel query returns data before calling it done (loop over `panels[].targets[].expr` against
  `/api/v1/query`).
- Generic knobs (units, process groups, probes, textfile dir) are Nix options in the host file under
  `home-manager/hosts/`; corp/private detail stays in the private host repo, never in dotfiles.

## Operating the stack

`systemctl --user status box-telemetry.service` (oneshot: `docker compose -p observability up -d`, re-run by a
10-min timer so a dirty reboot cannot leave Prometheus down), `docker compose -p observability ps`,
`docker logs <container>`. Config files are Nix store paths bind-mounted into the containers; `home-manager
switch` recreates only the containers whose config changed. The named volumes `observability_prometheus-data`
and `observability_grafana-data` hold all history -- never `docker compose down -v`.

Known pitfalls: node_exporter's systemd collector needs `apparmor=unconfined` on Ubuntu (D-Bus); a `pkill -f`
pattern that also appears in your own command line kills your shell; the box cannot reach its own
userspace-Tailscale IP, test from a peer.
