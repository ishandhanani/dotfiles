# Telemetry configuration

## Telemetry And Observability

Use first-class `srt-slurm` config. Do not embed raw tachometer/scraper commands in benchmark YAML.

- `telemetry:` is the metrics scraper path. It generates `telemetry_config.toml`, starts DCGM/node exporters, scrapes backend/frontend metrics from the rendered topology, and stores artifacts under `logs/<storage_subdir>`.
- `observability:` is for OTEL tracing env injection (`enable_otel`, `otel_endpoint`), not metrics scraping.
- Resolve `container_image`, `dcgm_exporter.container_image`, and `node_exporter.container_image` through `srtslurm.yaml` container aliases when possible.

Telemetry YAML shape:

```yaml
telemetry:
  enabled: true
  container_image: "telemetry-scraper"
  storage_subdir: "telemetry"
  default_frequency: 1.0
  sync_interval_secs: 0
  dcgm_exporter:
    container_image: "dcgm-exporter"
    port: 9401
  node_exporter:
    container_image: "node-exporter"
    port: 9101
```

Optional OTEL tracing:

```yaml
observability:
  enable_otel: true
  otel_endpoint: "http://<otel-collector>:4317"
```

For standalone `--bash` lifecycle behavior, use the renderer's built-in telemetry hooks and controls (`SRTCTL_ENABLE_TACHOMETER`, `SRTCTL_REQUIRE_TACHOMETER`, `SRTCTL_TACHOMETER_ARGS`) only when debugging that path. Prefer YAML-level `telemetry:` for normal recipes.
