#!/usr/bin/env python3
"""Generate dashboards/box.json: the one small dashboard provisioned by modules/box-telemetry.nix.

Eight panels over metrics the module itself scrapes (node_exporter; blackbox `dns` job when a host
declares probes). Add host-specific panels as extra dashboards under ~/.config/box-telemetry/dashboards/,
not here. Re-run after editing and commit the JSON.
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "dashboards", "box.json")
GOOD, CRITICAL, WARNING = "#0ca30c", "#d03b3b", "#fab219"   # status colors only; series use the default palette
DS = {"type": "prometheus", "uid": "prometheus"}
_ref = iter("ABCDEFGHIJKLMNOP")


def target(expr, legend=""):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": next(_ref), "range": True}


def grid(x, y, w, h):
    return {"x": x, "y": y, "w": w, "h": h}


def stat(title, expr, unit, gp, decimals=0, warn=None, crit=None):
    steps = [{"color": GOOD, "value": None}, {"color": WARNING, "value": warn}, {"color": CRITICAL, "value": crit}]
    return {"type": "stat", "title": title, "datasource": DS, "gridPos": gp, "targets": [target(expr)],
            "fieldConfig": {"defaults": {"unit": unit, "decimals": decimals, "color": {"mode": "thresholds"},
                                         "thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []},
            "options": {"colorMode": "value", "graphMode": "area", "textMode": "value", "justifyMode": "center",
                        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}}


def timeline(title, expr, legend, gp, up, down):
    return {"type": "state-timeline", "title": title, "datasource": DS, "gridPos": gp, "targets": [target(expr, legend)],
            "fieldConfig": {"defaults": {
                "color": {"mode": "thresholds"}, "custom": {"lineWidth": 0, "fillOpacity": 85},
                "thresholds": {"mode": "absolute", "steps": [{"color": CRITICAL, "value": None}, {"color": GOOD, "value": 1}]},
                "mappings": [{"type": "value", "options": {"0": {"text": down, "color": CRITICAL, "index": 0},
                                                           "1": {"text": up, "color": GOOD, "index": 1}}}]},
                "overrides": []},
            "options": {"mergeValues": True, "showValue": "never", "alignValue": "left", "rowHeight": 0.8,
                        "legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                        "tooltip": {"mode": "single", "sort": "none"}}}


def timeseries(title, targets, unit, gp, decimals=None):
    d = {"unit": unit, "color": {"mode": "palette-classic"},
         "custom": {"drawStyle": "line", "lineWidth": 2, "fillOpacity": 0, "showPoints": "never", "pointSize": 8,
                    "spanNulls": False, "axisSoftMin": 0, "stacking": {"mode": "none"}}}
    if decimals is not None:
        d["decimals"] = decimals
    return {"type": "timeseries", "title": title, "datasource": DS, "gridPos": gp, "targets": targets,
            "fieldConfig": {"defaults": d, "overrides": []},
            "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                        "tooltip": {"mode": "multi", "sort": "desc"}}}


panels = [
    stat("CPU busy", '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))', "percent", grid(0, 0, 8, 4), 0, 70, 90),
    stat("Memory used", '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', "percent", grid(8, 0, 8, 4), 0, 80, 92),
    stat("Disk used (/)", '100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})', "percent", grid(16, 0, 8, 4), 0, 80, 92),
    timeseries("Load (1m) vs cores", [target("node_load1", "load1"), target('count(node_cpu_seconds_total{mode="idle"})', "cores")], "none", grid(0, 4, 12, 7), 1),
    timeseries("Network throughput by interface (rx +, tx -)", [
        target('rate(node_network_receive_bytes_total{device!~"lo|veth.*|br-.*|docker.*"}[1m])', "{{device}} rx"),
        target('-rate(node_network_transmit_bytes_total{device!~"lo|veth.*|br-.*|docker.*"}[1m])', "{{device}} tx"),
    ], "Bps", grid(12, 4, 12, 7)),
    timeline("systemd units", 'node_systemd_unit_state{state="active"}', "{{name}}", grid(0, 11, 12, 7), "active", "inactive"),
    timeline("DNS answers by resolver", 'probe_success{job=~"dns.*"}', "{{resolver}}", grid(12, 11, 12, 7), "answering", "no answer"),
    timeseries("Disk free (/)", [target('node_filesystem_avail_bytes{mountpoint="/"}', "free")], "bytes", grid(0, 18, 24, 6)),
]

dashboard = {
    "uid": "box", "title": "box", "tags": ["box-telemetry"], "timezone": "browser", "schemaVersion": 39,
    "version": 1, "editable": True, "graphTooltip": 1, "time": {"from": "now-6h", "to": "now"}, "refresh": "30s",
    "templating": {"list": []}, "annotations": {"list": []}, "links": [], "panels": panels,
}

if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(dashboard, open(OUT, "w"), indent=2)
    print(OUT, len(panels), "panels")
