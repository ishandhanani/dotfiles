#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Run fresh, read-only Claude verification prompts in parallel."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--add-dir", action="append", default=[], type=Path)
    parser.add_argument("--prompt", action="append", required=True)
    parser.add_argument("--model")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    return parser.parse_args()


def ask(index: int, prompt: str, args: argparse.Namespace) -> dict:
    command = [
        "claude",
        "-p",
        "--safe-mode",
        "--permission-mode",
        "plan",
        "--no-session-persistence",
        "--output-format",
        "json",
    ]
    if args.model:
        command.extend(["--model", args.model])
    for directory in args.add_dir:
        command.extend(["--add-dir", str(directory.resolve())])
    command.append(prompt)

    try:
        completed = subprocess.run(
            command,
            cwd=args.cwd,
            capture_output=True,
            text=True,
            timeout=args.timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        return {"friend": index, "ok": False, "error": f"timed out after {error.timeout}s"}
    except OSError as error:
        return {"friend": index, "ok": False, "error": str(error)}

    result = {
        "friend": index,
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
    }
    if completed.stderr.strip():
        result["stderr"] = completed.stderr.strip()
    try:
        result["response"] = json.loads(completed.stdout)
        if isinstance(result["response"], dict) and result["response"].get("is_error"):
            result["ok"] = False
    except json.JSONDecodeError:
        result["stdout"] = completed.stdout.strip()
    return result


def main() -> int:
    args = parse_args()
    if shutil.which("claude") is None:
        print(json.dumps({"error": "claude executable not found"}))
        return 127
    if not args.cwd.is_dir():
        print(json.dumps({"error": f"cwd is not a directory: {args.cwd}"}))
        return 2
    if args.timeout_seconds <= 0:
        print(json.dumps({"error": "timeout-seconds must be positive"}))
        return 2

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(args.prompt)) as pool:
        futures = [pool.submit(ask, index, prompt, args) for index, prompt in enumerate(args.prompt, 1)]
        results = [future.result() for future in futures]

    print(json.dumps(results, indent=2))
    return 0 if all(result["ok"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
