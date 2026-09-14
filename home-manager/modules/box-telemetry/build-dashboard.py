#!/usr/bin/env python3
"""Generate dashboards/box.json -- the generic box dashboard provisioned by modules/box-telemetry.nix.

Panels only reference metrics the module itself scrapes (node_exporter, process-exporter, blackbox
`https`/`dns` jobs), so it works on any box. Host-specific tiles belong in a private extra dashboard
under ~/.config/box-telemetry/dashboards/. Re-run after editing and commit the JSON.
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "dashboards", "box.json")

# Status colors are fixed and never reused for series (dataviz skill). Series use Grafana's palette.
GOOD, CRITICAL, WARNING = "#0ca30c", "#d03b3b", "#fab219"
DS = {"type": "prometheus", "uid": "prometheus"}
_ref = iter("ABCDEFGHIJKLMNOPQRSTUVWXYZ")


def target(expr, legend):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": next(_ref), "range": True}


def grid(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def row(title, y):
    return {"type": "row", "title": title, "collapsed": False, "gridPos": grid(0, y, 24, 1), "panels": []}


def stat_updown(title, expr, up, down, gp):
    return {
        "type": "stat", "title": title, "datasource": DS, "gridPos": gp, "targets": [target(expr, "")],
        "fieldConfig": {"defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {"mode": "absolute", "steps": [{"color": CRITICAL, "value": None}, {"color": GOOD, "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": down, "color": CRITICAL, "index": 0},
                                                       "1": {"text": up, "color": GOOD, "index": 1}}}]},
            "overrides": []},
        "options": {"colorMode": "background", "graphMode": "none", "textMode": "value", "justifyMode": "center",
                    "orientation": "auto", "wideLayout": True,
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}},
    }


def stat_num(title, expr, unit, gp, decimals=0, thresholds=None):
    steps = [{"color": "text", "value": None}]
    mode = "none"
    if thresholds:
        steps = [{"color": GOOD, "value": None}] + [{"color": c, "value": v} for v, c in thresholds]
        mode = "value"
    return {
        "type": "stat", "title": title, "datasource": DS, "gridPos": gp, "targets": [target(expr, "")],
        "fieldConfig": {"defaults": {"unit": unit, "decimals": decimals, "color": {"mode": "thresholds"},
                                     "thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []},
        "options": {"colorMode": mode, "graphMode": "area", "textMode": "value", "justifyMode": "center",
                    "orientation": "auto", "wideLayout": True,
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}},
    }


def timeline(title, expr, legend, gp, up="up", down="down"):
    return {
        "type": "state-timeline", "title": title, "datasource": DS, "gridPos": gp, "targets": [target(expr, legend)],
        "fieldConfig": {"defaults": {
            "color": {"mode": "thresholds"}, "custom": {"lineWidth": 0, "fillOpacity": 85},
            "thresholds": {"mode": "absolute", "steps": [{"color": CRITICAL, "value": None}, {"color": GOOD, "value": 1}]},
            "mappings": [{"type": "value", "options": {"0": {"text": down, "color": CRITICAL, "index": 0},
                                                       "1": {"text": up, "color": GOOD, "index": 1}}}]},
            "overrides": []},
        "options": {"mergeValues": True, "showValue": "never", "alignValue": "left", "rowHeight": 0.8,
                    "legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "single", "sort": "none"}},
    }


def timeseries(title, targets, unit, gp, decimals=None, soft_min=0, dashed=()):
    defaults = {"unit": unit, "color": {"mode": "palette-classic"},
                "custom": {"drawStyle": "line", "lineInterpolation": "linear", "lineWidth": 2, "fillOpacity": 0,
                           "gradientMode": "none", "showPoints": "never", "pointSize": 8, "spanNulls": False,
                           "axisPlacement": "auto", "axisSoftMin": soft_min, "stacking": {"mode": "none"}}}
    if decimals is not None:
        defaults["decimals"] = decimals
    overrides = [{"matcher": {"id": "byRegexp", "options": d},
                  "properties": [{"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [10, 10]}}]} for d in dashed]
    return {"type": "timeseries", "title": title, "datasource": DS, "gridPos": gp, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": overrides},
            "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                        "tooltip": {"mode": "multi", "sort": "desc"}}}


def build():
    p, y = [], 0
    p.append(row("Reachability -- from this box", y)); y += 1
    p += [
        stat_updown("Public DNS (system resolver)", 'probe_success{job="dns",resolver="system"}', "RESOLVING", "DEAD", grid(0, y, 8, 3)),
        stat_num("HTTPS sites reachable", 'sum(probe_success{job="https"})', "none", grid(8, y, 8, 3)),
        stat_num("HTTPS sites probed", 'count(probe_success{job="https"})', "none", grid(16, y, 8, 3)),
    ]; y += 3
    p += [
        timeline("DNS answers by resolver", 'probe_success{job=~"dns.*"}', "{{resolver}}", grid(0, y, 12, 6), "answering", "no answer"),
        timeseries("DNS lookup time by resolver", [target('probe_duration_seconds{job=~"dns.*"}', "{{resolver}}")], "s", grid(12, y, 12, 6), decimals=3),
    ]; y += 6
    p += [
        timeline("HTTPS reachability by site", 'probe_success{job="https"}', "{{site}}", grid(0, y, 12, 6), "reachable", "unreachable"),
        timeseries("HTTPS probe duration by site", [target('probe_duration_seconds{job="https"}', "{{site}}")], "s", grid(12, y, 12, 6), decimals=2),
    ]; y += 6

    p.append(row("Network", y)); y += 1
    p += [
        timeseries("Throughput by interface (rx solid, tx dashed)", [
            target('rate(node_network_receive_bytes_total{device!~"lo|veth.*|br-.*"}[1m])', "{{device}} rx"),
            target('rate(node_network_transmit_bytes_total{device!~"lo|veth.*|br-.*"}[1m])', "{{device}} tx"),
        ], "Bps", grid(0, y, 12, 7), dashed=(".* tx",)),
        timeseries("Kernel routes by device", [target('count by (device) (node_network_route_info)', "{{device}}")], "none", grid(12, y, 12, 7), decimals=0),
    ]; y += 7

    p.append(row("Services & processes", y)); y += 1
    p += [
        timeline("systemd units (system scope)", 'node_systemd_unit_state{state="active"}', "{{name}}", grid(0, y, 12, 8), "active", "inactive"),
        timeline("Process presence", 'namedprocess_namegroup_num_procs > bool 0', "{{groupname}}", grid(12, y, 12, 8), "running", "absent"),
    ]; y += 8
    p += [
        timeseries("Process CPU", [target('sum by (groupname) (rate(namedprocess_namegroup_cpu_seconds_total[2m])) * 100', "{{groupname}}")], "percent", grid(0, y, 12, 7), decimals=1),
        timeseries("Process resident memory", [target('sum by (groupname) (namedprocess_namegroup_memory_bytes{memtype="resident"})', "{{groupname}}")], "bytes", grid(12, y, 12, 7)),
    ]; y += 7

    p.append(row("Box health", y)); y += 1
    p += [
        stat_num("CPU busy", '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))', "percent", grid(0, y, 6, 4), 0, [(70, WARNING), (90, CRITICAL)]),
        stat_num("Load (1m) per core", 'node_load1 / count(node_cpu_seconds_total{mode="idle"})', "none", grid(6, y, 6, 4), 2, [(1, WARNING), (2, CRITICAL)]),
        stat_num("Memory used", '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', "percent", grid(12, y, 6, 4), 0, [(80, WARNING), (92, CRITICAL)]),
        stat_num("Disk used (/)", '100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})', "percent", grid(18, y, 6, 4), 0, [(80, WARNING), (92, CRITICAL)]),
    ]; y += 4
    p += [
        timeseries("CPU busy %", [target('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m])))', "busy")], "percent", grid(0, y, 8, 7), decimals=0),
        timeseries("Memory", [target('node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes', "used"), target('node_memory_MemTotal_bytes', "total")], "bytes", grid(8, y, 8, 7)),
        timeseries("Disk free (/)", [target('node_filesystem_avail_bytes{mountpoint="/"}', "free")], "bytes", grid(16, y, 8, 7)),
    ]; y += 7

    return {
        "uid": "box-telemetry", "title": "box -- reachability, network, services, health",
        "tags": ["box-telemetry"], "timezone": "browser", "schemaVersion": 39, "version": 1, "editable": True,
        "graphTooltip": 1, "time": {"from": "now-6h", "to": "now"}, "refresh": "30s",
        "templating": {"list": []}, "annotations": {"list": []}, "links": [], "panels": p,
    }


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(build(), open(OUT, "w"), indent=2)
    print(OUT)
