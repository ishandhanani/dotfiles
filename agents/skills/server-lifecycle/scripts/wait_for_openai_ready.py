#!/usr/bin/env python3
"""Poll OpenAI-compatible readiness endpoints until a model is usable."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def get_json(url: str, timeout: float) -> tuple[int | None, object | None, str | None]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, json.loads(body), None
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            data: object | None = json.loads(body)
        except json.JSONDecodeError:
            data = None
        return exc.code, data, body[:200]
    except Exception as exc:  # noqa: BLE001 - readiness probes should report any transport error.
        return None, None, str(exc)


def parse_expect_worker(values: list[str]) -> dict[str, int]:
    expected: dict[str, int] = {}
    for value in values:
        if "=" not in value:
            raise SystemExit(f"--expect-worker must be TYPE=N, got {value!r}")
        name, raw_count = value.split("=", 1)
        try:
            expected[name] = int(raw_count)
        except ValueError as exc:
            raise SystemExit(f"invalid worker count in {value!r}") from exc
    return expected


def model_listed(models: object, model: str) -> bool:
    if not isinstance(models, dict):
        return False
    data = models.get("data")
    if not isinstance(data, list):
        return False
    return any(isinstance(row, dict) and row.get("id") == model for row in data)


def ready_worker_counts(ready: object) -> dict[str, int]:
    counts: dict[str, int] = {}
    if not isinstance(ready, dict):
        return counts
    namespaces = ready.get("namespaces")
    if not isinstance(namespaces, dict):
        return counts
    for namespace in namespaces.values():
        if not isinstance(namespace, dict):
            continue
        worker_types = namespace.get("worker_types")
        if not isinstance(worker_types, dict):
            continue
        for name, info in worker_types.items():
            if not isinstance(info, dict):
                continue
            workers = info.get("workers", 0)
            if isinstance(workers, int):
                counts[str(name)] = counts.get(str(name), 0) + workers
    return counts


def ready_ok(ready: object, expected_workers: dict[str, int]) -> tuple[bool, str]:
    if not isinstance(ready, dict):
        return False, "ready endpoint returned non-object JSON"
    if ready.get("ready") is not True:
        return False, str(ready.get("reason") or "model readiness is false")
    counts = ready_worker_counts(ready)
    for name, expected in expected_workers.items():
        actual = counts.get(name, 0)
        if actual < expected:
            return False, f"{name} workers {actual} < {expected}"
    return True, "ready"


def health_ok(health: object, min_instances: int) -> tuple[bool, str]:
    if min_instances <= 0:
        return True, "not required"
    if not isinstance(health, dict):
        return False, "health endpoint returned non-object JSON"
    instances = health.get("instances")
    count = len(instances) if isinstance(instances, list) else 0
    if count < min_instances:
        return False, f"health instances {count} < {min_instances}"
    return True, f"health instances {count}"


def pid_alive(pid: int | None) -> bool:
    if pid is None:
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--model", required=True)
    parser.add_argument("--timeout", type=float, default=3600)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--request-timeout", type=float, default=3)
    parser.add_argument("--watch-pid", type=int, help="Fail if this local server PID exits.")
    parser.add_argument(
        "--expect-worker",
        action="append",
        default=[],
        help="Require at least TYPE=N workers from /v1/models/<model>/ready. Repeatable.",
    )
    parser.add_argument(
        "--min-health-instances",
        type=int,
        default=0,
        help="Also require /health to report at least this many discovery instances.",
    )
    parser.add_argument("--verbose", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    base_url = args.base_url.rstrip("/")
    model_path = urllib.parse.quote(args.model, safe="/:-_.")
    expected_workers = parse_expect_worker(args.expect_worker)
    deadline = time.monotonic() + args.timeout
    last = "not checked"

    while time.monotonic() < deadline:
        if not pid_alive(args.watch_pid):
            print(f"NOT_READY model={args.model} server_pid_exited={args.watch_pid}", file=sys.stderr)
            return 1

        model_status, models, model_error = get_json(
            f"{base_url}/v1/models", args.request_timeout
        )
        listed = model_status == 200 and model_listed(models, args.model)

        ready_status, ready, ready_error = get_json(
            f"{base_url}/v1/models/{model_path}/ready", args.request_timeout
        )
        has_ready_endpoint = ready_status == 200
        ready_pass, ready_reason = (
            ready_ok(ready, expected_workers)
            if has_ready_endpoint
            else (False, ready_error or f"ready status {ready_status}")
        )

        health_status, health, health_error = get_json(
            f"{base_url}/health", args.request_timeout
        )
        health_pass, health_reason = health_ok(
            health if health_status == 200 else None, args.min_health_instances
        )
        if health_status != 200 and args.min_health_instances > 0:
            health_reason = health_error or f"health status {health_status}"

        ready_gate = ready_pass if has_ready_endpoint else listed
        if ready_gate and health_pass:
            counts = ready_worker_counts(ready)
            suffix = f" workers={counts}" if counts else ""
            print(f"READY model={args.model} {ready_reason}; {health_reason}{suffix}")
            return 0

        last = (
            f"listed={listed} ready={ready_status}:{ready_reason} "
            f"health={health_status}:{health_reason} model_error={model_error}"
        )
        if args.verbose:
            print(f"[{time.strftime('%H:%M:%S')}] {last}", file=sys.stderr)
        time.sleep(args.interval)

    print(f"NOT_READY model={args.model} last={last}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
