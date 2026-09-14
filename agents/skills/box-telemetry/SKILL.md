---
name: box-telemetry
description: Debug a Linux box that runs the dotfiles boxTelemetry stack. Use when asked whether something on that machine is up, slow or broken, what it is doing (services, DNS, tunnels, disk, load), or when an incident needs a timeline.
---

# Box telemetry

The box measures itself: Prometheus `:9091`, Grafana `:3001` (dashboard `box`), node_exporter with the
systemd and route collectors, and blackbox probes when the host declares any. 90 days of history.
Read the data before running commands: data answers "since when", a shell only answers "now".

1. `scripts/box-snapshot` -- the whole box in ~40 lines (health, failed units, probes, routes, containers,
   recent errors). Works even when Prometheus is down.
2. `scripts/boxq '<promql>'` for a value now; `--range 2h` for a timeline; `--targets` for what is scraped.
   Metric names by question: `reference/metrics.md`.
3. Shell, only for what has no metric (a config file, a specific log line, a one-off test).

Remote: `ssh <box> '~/.claude/skills/box-telemetry/scripts/box-snapshot'`. This harness rewrites bare
`ssh`/`rm` (`mssh`/`mrm`); use `/usr/bin/ssh` in scripts.

Host-private facts (corp resolvers, tunnel daemons, credentials) are not in this repo: read the box's doc under
`~/memory/compute/` when present, and `~/.config/box-telemetry/scrape.d/` for its private probes.
Extending or operating the stack: `reference/operate.md`.
