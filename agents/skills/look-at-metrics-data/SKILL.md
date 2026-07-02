---
name: look-at-metrics-data
description: Investigate benchmark telemetry from Tachometer Parquet, Prometheus snapshots, SGLang and Dynamo logs, traces, and cache/storage metrics. Use when diagnosing throughput, latency, routing, KV-cache, HiCache, or storage-tier behavior; validating a benchmark; or explaining why an observed metric changed.
---

# Investigate Metrics Data

Start with evidence, not a theory. Diagnose only unless the user asks for a change.

## Establish the experiment

1. Record the exact arm/config difference, model and worker topology, load shape, warmup and measurement boundaries, and benchmark completion state.
2. Inventory raw artifacts before querying: Tachometer Parquet, Prometheus before/after snapshots, server/router logs, workload results, and request/audit traces.
3. Verify Tachometer covers the measured interval, expected endpoints were scraped, and the server stayed up. State missing artifacts explicitly.
4. Keep results scoped to the common time window. Do not use whole-capture totals when warmup, teardown, or restart is included.

## Discover before aggregating

Inspect the Parquet schema and enumerate metric names, endpoints, and label sets first. Do not guess a metric name from implementation or documentation.

```bash
python3 - <<'PY'
import pyarrow.parquet as pq
t = pq.read_table("/path/to/final.parquet")
print(t.schema)
print(t.column_names)
PY
```

Use PyArrow, DuckDB, or an available reader. Adapt to the actual schema. For each candidate metric, print metric name, endpoint/full labels, first and last timestamp/value per series, sample count, monotonicity, and raw rows. Treat series identity as metric name plus every label. Aggregate only after selecting exact series identities.

## Apply the right math

| Series kind | Report |
|---|---|
| Counter | Window delta: last at/before end minus first at/after start. Split resets; never subtract across one. |
| Gauge | Time series plus min/median/max or time-weighted average. Always pair capacity used with configured capacity. |
| Histogram | Derive quantiles from cumulative `_bucket` deltas/rates; never sum buckets as independent observations. |
| Summary | Keep quantile labels separate; do not average quantiles across workers. |

Show boundary timestamps and values for every delta. If samples are sparse, call the boundary approximate. Never derive a rate from a final counter alone.

## Preserve topology and labels

- Group per endpoint/worker before a cluster total. Check whether TP/DP ranks export replicas of the same logical counter.
- Count a TP-replicated service-level counter once only after confirming identical values and synchronized resets. Otherwise report per-rank values; do not blindly divide by TP size.
- Keep cache source, model, backend, request class, and worker labels in the first table. Dropping labels early can turn a storage miss into an apparent hit.
- Correlate wall-clock and relative elapsed timestamps explicitly. Do not align independently started scrapers by row number.

## Investigate cache and storage as a pipeline

```text
request/routing -> GPU cache -> host cache -> storage lookup -> restore -> execution
                 \-> eviction/write-back -> storage allocation/eviction
```

For each edge, seek a direct signal:

- request count, prompt tokens, cached/recomputed tokens, and cache-source labels;
- device and host occupancy/capacity over time;
- eviction and write-back counters;
- storage puts, metadata lookups, restored tokens, allocated bytes, and store evictions;
- scheduler pause/resume/queue signals and request latency.

Do not equate these signals:

- Write-back proves upper-tier eviction, not future reuse.
- A storage lookup proves an attempt, not a data transfer or hit.
- Store occupancy proves retention, not usefulness.
- A prefetch policy name does not prove proactive prefetch; check the operation counter and request-time control path.

If a transition has no metric, say so. Do not reconstruct per-request behavior from aggregate counters or infer HTTP headers/session identity from a body-only audit.

## Triangulate implementation and runtime

When telemetry is ambiguous:

1. Read live server logs/config to establish backend, policy, thresholds, and defaults.
2. Use `rg` to locate the metric definition and every increment/observation. Trace callers and guard conditions.
3. Match each guard to a runtime config value and observed metric/log event.
4. Separate what source permits from what the run demonstrably did.

Use source to explain a measured event, not to replace the measurement. Prefer the smallest query or log excerpt that can falsify the hypothesis.

## Make causal claims conservatively

- Distinguish mechanism activity, workload change, and performance effect.
- A single ordered live-agent A->B pair is directional only; trajectories, load, cache warmness, and order can differ.
- Require matched replay or randomized A/B and B/A repetitions before attributing throughput or quality to a cache feature.
- Report absolute counts and denominators. A nonzero restore counter may still be negligible relative to prompt tokens or recomputation.
- Name alternative explanations that remain unmeasured; do not call an inactive path overhead or benefit.

## Deliverable

Return a compact evidence table with exact time window, topology/label treatment, primary deltas, and artifact coverage. Then state:

1. what happened directly;
2. which pipeline transition explains it, if proven;
3. what is unknown and the one missing measurement or controlled run needed next.

Preserve the query/command behind every reported number. Correct earlier conclusions immediately when schema discovery disproves an assumption.

