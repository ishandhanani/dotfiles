# Metrics by question

Prometheus API: `localhost:9091/api/v1/query?query=...` (instant), `/query_range?start=&end=&step=` (history),
`/targets`. `scripts/boxq` wraps these with compact output.

| Question | Query |
|---|---|
| Does DNS work, per resolver? | `probe_success{job=~"dns.*"}` (`resolver` label); latency `probe_duration_seconds{job=~"dns.*"}` |
| Can the box reach site S? | `probe_success{job="https",site="S"}`, `probe_http_status_code` |
| Is an auth lock still on? | `probe_success{job="<auth_required job>"}` (module passes only on HTTP 401) |
| Is system unit U running? | `node_systemd_unit_state{name="U.service",state="active"}` -- `systemd --user` units are invisible here |
| Interface traffic | `rate(node_network_receive_bytes_total{device="D"}[1m])` / `..._transmit_...` |
| Is route R installed, on which device? | `node_network_route_info{dest="R"}` (labels `device`, `dest`, `proto`); `count by (device) (node_network_route_info)` |
| Tunnel up? | tun devices always report operstate unknown: use their routes (`node_network_route_info{device="tun0"}`) or a probe through them, not `node_network_up` |
| Disk / memory / CPU / load | `node_filesystem_avail_bytes{mountpoint="/"}`, `node_memory_MemAvailable_bytes`, `1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))`, `node_load1` |
| Custom gauges from cron scripts | any `*.prom` written into `boxTelemetry.textfileDir` |
| What is scraped / broken? | `/api/v1/targets` -> `health`, `lastError` per job |

Incident timeline: `boxq '<query>' --range 6h` and read where `probe_success` or `node_systemd_unit_state` flipped.
