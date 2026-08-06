#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Run fresh friend agents in parallel across claude / agent / devin."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

FRIENDS = ("claude", "agent", "devin")
SPEEDS = ("fast", "balanced", "deep")
CAPABILITIES = ("verify", "act")

# speed -> default friend when --friend auto
SPEED_DEFAULT_FRIEND = {
    "fast": "devin",
    "balanced": "claude",
    "deep": "claude",
}

# (friend, speed) -> default model; None means CLI default
DEFAULT_MODELS: dict[tuple[str, str], str | None] = {
    ("devin", "fast"): "swe-1-7-lightning",
    ("devin", "balanced"): "claude-sonnet-5-high",
    ("devin", "deep"): "claude-opus-4-8-high",
    ("agent", "fast"): "composer-2.5-fast",
    ("agent", "balanced"): "cursor-grok-4.5-high",
    ("agent", "deep"): "claude-opus-5-thinking-high",
    ("claude", "fast"): None,
    ("claude", "balanced"): None,
    ("claude", "deep"): "opus",
}


@dataclass(frozen=True)
class Resolved:
    friend: str
    speed: str
    capability: str
    model: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--add-dir", action="append", default=[], type=Path)
    parser.add_argument("--prompt", action="append", required=True)
    parser.add_argument("--speed", choices=SPEEDS, default="balanced")
    parser.add_argument("--friend", choices=("auto", *FRIENDS), default="auto")
    parser.add_argument("--capability", choices=CAPABILITIES, default="verify")
    parser.add_argument("--model", help="Override the profile default model")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print resolved profile + commands as JSON; do not execute",
    )
    return parser.parse_args()


def resolve(args: argparse.Namespace) -> Resolved:
    friend = SPEED_DEFAULT_FRIEND[args.speed] if args.friend == "auto" else args.friend
    model = args.model if args.model is not None else DEFAULT_MODELS[(friend, args.speed)]
    return Resolved(
        friend=friend,
        speed=args.speed,
        capability=args.capability,
        model=model,
    )


def build_claude(prompt: str, resolved: Resolved, args: argparse.Namespace) -> list[str]:
    command = ["claude", "-p", "--no-session-persistence", "--output-format", "json"]
    if resolved.capability == "verify":
        command.extend(["--safe-mode", "--permission-mode", "plan"])
    else:
        command.extend(["--permission-mode", "bypassPermissions"])
    if resolved.model:
        command.extend(["--model", resolved.model])
    for directory in args.add_dir:
        command.extend(["--add-dir", str(directory.resolve())])
    command.append(prompt)
    return command


def build_agent(prompt: str, resolved: Resolved, args: argparse.Namespace) -> list[str]:
    command = [
        "agent",
        "-p",
        "--output-format",
        "json",
        "--workspace",
        str(args.cwd.resolve()),
        "--trust",
    ]
    if resolved.capability == "verify":
        command.extend(["--mode", "plan"])
    else:
        command.append("--yolo")
    if resolved.model:
        command.extend(["--model", resolved.model])
    for directory in args.add_dir:
        command.extend(["--add-dir", str(directory.resolve())])
    command.append(prompt)
    return command


def build_devin(prompt: str, resolved: Resolved, args: argparse.Namespace) -> list[str]:
    # Devin has no structured --output-format; stdout is plain text.
    # --add-dir is unsupported; extra roots must be named in the prompt.
    permission = "auto" if resolved.capability == "verify" else "dangerous"
    command = [
        "devin",
        "--permission-mode",
        permission,
        "--respect-workspace-trust",
        "false",
    ]
    if resolved.model:
        command.extend(["--model", resolved.model])
    command.extend(["-p", prompt])
    return command


BUILDERS: dict[str, Callable[[str, Resolved, argparse.Namespace], list[str]]] = {
    "claude": build_claude,
    "agent": build_agent,
    "devin": build_devin,
}


def ask(index: int, prompt: str, resolved: Resolved, args: argparse.Namespace) -> dict:
    command = BUILDERS[resolved.friend](prompt, resolved, args)
    meta = {
        "friend": index,
        "backend": resolved.friend,
        "speed": resolved.speed,
        "capability": resolved.capability,
        "model": resolved.model,
        "command": command,
    }
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
        return {**meta, "ok": False, "error": f"timed out after {error.timeout}s"}
    except OSError as error:
        return {**meta, "ok": False, "error": str(error)}

    result = {
        **meta,
        "ok": completed.returncode == 0,
        "returncode": completed.returncode,
    }
    if completed.stderr.strip():
        result["stderr"] = completed.stderr.strip()
    stdout = completed.stdout.strip()
    if not stdout:
        return result
    try:
        result["response"] = json.loads(stdout)
        if isinstance(result["response"], dict) and result["response"].get("is_error"):
            result["ok"] = False
    except json.JSONDecodeError:
        result["stdout"] = stdout
    return result


def main() -> int:
    args = parse_args()
    if not args.cwd.is_dir():
        print(json.dumps({"error": f"cwd is not a directory: {args.cwd}"}))
        return 2
    if args.timeout_seconds <= 0:
        print(json.dumps({"error": "timeout-seconds must be positive"}))
        return 2
    resolved = resolve(args)
    if resolved.friend == "devin" and args.add_dir:
        print(
            json.dumps(
                {
                    "error": (
                        "devin does not support --add-dir; pass --friend claude|agent "
                        "or name extra roots in the prompt"
                    ),
                }
            )
        )
        return 2
    if shutil.which(resolved.friend) is None:
        print(json.dumps({"error": f"{resolved.friend} executable not found"}))
        return 127

    if args.dry_run:
        commands = [
            {
                "friend": index,
                "backend": resolved.friend,
                "speed": resolved.speed,
                "capability": resolved.capability,
                "model": resolved.model,
                "command": BUILDERS[resolved.friend](prompt, resolved, args),
            }
            for index, prompt in enumerate(args.prompt, 1)
        ]
        print(json.dumps({"resolved": resolved.__dict__, "commands": commands}, indent=2))
        return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(args.prompt)) as pool:
        futures = [
            pool.submit(ask, index, prompt, resolved, args)
            for index, prompt in enumerate(args.prompt, 1)
        ]
        results = [future.result() for future in futures]

    print(json.dumps(results, indent=2))
    return 0 if all(result["ok"] for result in results) else 1


if __name__ == "__main__":
    sys.exit(main())
