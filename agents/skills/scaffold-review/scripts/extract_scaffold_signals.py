#!/usr/bin/env python3
"""Extract compact scaffold-review signals from local agent session logs."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


INJECTED_PREFIXES = (
    "# AGENTS.md instructions",
    "# CLAUDE.md instructions",
    "<skill>",
    "<environment_context>",
    "<developer_context>",
    "<permissions instructions>",
    "<app-context>",
    "<collaboration_mode>",
    "<apps_instructions>",
    "<skills_instructions>",
    "<plugins_instructions>",
    "<subagent_notification>",
    "<local-command-caveat>",
    "<command-name>",
    "<command-message>",
    "<local-command-stdout>",
    "<turn_aborted>",
)
TEXT_BLOCK_TYPES = {"text", "input_text", "output_text"}
SUBAGENT_TOOL_NAMES = {"spawn_agent", "wait_agent", "send_input", "close_agent", "resume_agent"}

CORRECTION_RE = re.compile(
    r"\b("
    r"actually|no,|no\b|don't|do not|dont|before we|first run|not what|"
    r"rather|instead|approval|permission|too many|too much|slop|specific|"
    r"ground yourself|let'?s discuss|missed|should|shouldn'?t|without|"
    r"wait\b|keep\b|ignore this|no need"
    r")\b",
    re.IGNORECASE,
)
STRONG_CORRECTION_RE = re.compile(
    r"^(actually|no\b|well what|before we|dont|don't|do not|it should|"
    r"if we|ok - also|now -|rather|instead|wait\b)",
    re.IGNORECASE,
)

PATH_RE = re.compile(
    r"("
    r"/(?:home|ephemeral|tmp)/[A-Za-z0-9_./+\-]+|"
    r"(?:agents|lib|python|examples|tests|src|scripts|docs|crates)/[A-Za-z0-9_./+\-]+"
    r")"
)
SKILL_RE = re.compile(r"(?:\$|skills/)([A-Za-z0-9_:-]+)")

PATTERNS: list[tuple[str, str, re.Pattern[str]]] = [
    (
        "github_pr_comments",
        "GitHub PR comment/review triage",
        re.compile(
            r"gh pr (view|diff|comment|checkout)|fetch_comments|review_comment|"
            r"_list_comments|_reply_to_review_comment|review comments?|address comments?",
            re.IGNORECASE,
        ),
    ),
    (
        "linear_issue_work",
        "Linear issue creation/update/scope work",
        re.compile(r"Linear|_save_issue|_list_issues|DYN-\d+", re.IGNORECASE),
    ),
    (
        "skill_scaffold_work",
        "Skill and scaffold editing",
        re.compile(
            r"skills/.+/SKILL\.md|agents/setup\.sh|\bskill\b|scaffold|"
            r"CLAUDE\.md|AGENTS\.md",
            re.IGNORECASE,
        ),
    ),
    (
        "insight_report_work",
        "Codex insight/report analysis",
        re.compile(
            r"insight-codex|usage-data|analysis-input|synthesis\.json|"
            r"generate_report|insights?",
            re.IGNORECASE,
        ),
    ),
    (
        "benchmark_server_lifecycle",
        "Server lifecycle and benchmark orchestration",
        re.compile(
            r"aiperf|benchmark|pkill|/health|/v1/models|nvidia-smi|"
            r"sglang\.launch_server|srtctl|CUDA_VISIBLE_DEVICES|perf benefit",
            re.IGNORECASE,
        ),
    ),
    (
        "git_publish",
        "Git commit/push/PR publishing",
        re.compile(
            r"git (status|add|commit|push|diff|log)|gh pr create|push this|push directly",
            re.IGNORECASE,
        ),
    ),
    (
        "memory_logging",
        "Memory worklog and registry updates",
        re.compile(r"/memory|~/memory|memory/INDEX|lint_memory|worklog", re.IGNORECASE),
    ),
    (
        "subagent_parallelism",
        "Subagent or review-bucket parallelism",
        re.compile(
            r"subagent|spawn_agent|multi-agent|parallel|different subagent|bucket [A-D] only",
            re.IGNORECASE,
        ),
    ),
    (
        "permission_approval_boundary",
        "Permission, approval, posting, and push boundaries",
        re.compile(
            r"approval|permission|ask before|do not call|no separate approval|"
            r"approved|don.?t post|no need to push|do not push",
            re.IGNORECASE,
        ),
    ),
    (
        "pr_description_management",
        "PR description/body maintenance",
        re.compile(
            r"PR description|pull request description|body_file|gh pr edit|"
            r"Benchmark Results|Walkthrough",
            re.IGNORECASE,
        ),
    ),
    (
        "minimality_review",
        "Scope trimming and minimality review",
        re.compile(
            r"ponytail|minimality|trim|bare minimum|too many|too much slop|simplest|scope",
            re.IGNORECASE,
        ),
    ),
]


def resolve_agent_home() -> Path:
    if os.environ.get("AGENT_HOME"):
        return Path(os.environ["AGENT_HOME"]).expanduser()
    if any(os.environ.get(k) for k in ("CODEX_HOME", "CODEX_THREAD_ID", "CODEX_CI")):
        return Path(os.environ.get("CODEX_HOME", "~/.codex")).expanduser()
    if any(os.environ.get(k) for k in ("CLAUDE_HOME", "CLAUDECODE", "CLAUDE_CODE")):
        return Path(os.environ.get("CLAUDE_HOME", "~/.claude")).expanduser()
    codex = Path("~/.codex/sessions").expanduser()
    claude_projects = Path("~/.claude/projects").expanduser()
    claude_sessions = Path("~/.claude/sessions").expanduser()
    claude_available = claude_projects.is_dir() or claude_sessions.is_dir()
    if codex.is_dir() and not claude_available:
        return codex.parent
    if claude_available and not codex.is_dir():
        return claude_projects.parent
    if codex.is_dir() and claude_available:
        raise SystemExit("Both Codex and Claude logs exist. Set AGENT_HOME or pass --agent-home explicitly.")
    raise SystemExit("Unable to infer AGENT_HOME. Set AGENT_HOME explicitly.")


def has_jsonl(root: Path) -> bool:
    try:
        next(root.rglob("*.jsonl"))
    except StopIteration:
        return False
    return True


def session_roots(agent_home: Path) -> list[Path]:
    sessions = agent_home / "sessions"
    projects = agent_home / "projects"
    roots: list[Path] = []
    if sessions.is_dir() and has_jsonl(sessions):
        roots.append(sessions)
    if projects.is_dir() and has_jsonl(projects):
        roots.append(projects)
    if roots:
        return roots
    if sessions.is_dir():
        return [sessions]
    if projects.is_dir():
        return [projects]
    raise SystemExit(f"No sessions or projects directory under {agent_home}")


def session_meta(path: Path) -> dict[str, Any]:
    try:
        with path.open(errors="ignore") as handle:
            for line in handle:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get("type") == "session_meta":
                    payload = obj.get("payload")
                    return payload if isinstance(payload, dict) else {}
                if obj.get("sessionId"):
                    return {"id": obj.get("sessionId")}
    except OSError:
        return {}
    return {}


def exclude_current_ids(extra: list[str] | None = None) -> set[str]:
    ids = {value for value in (extra or []) if value}
    if os.environ.get("CODEX_THREAD_ID"):
        ids.add(os.environ["CODEX_THREAD_ID"])
    return ids


def is_subagent_session(meta: dict[str, Any]) -> bool:
    if meta.get("thread_source") == "subagent":
        return True
    source = meta.get("source")
    return isinstance(source, dict) and "subagent" in source


def should_exclude_session(
    path: Path,
    meta: dict[str, Any],
    excluded_ids: set[str],
    include_subagents: bool,
) -> bool:
    if not include_subagents and is_subagent_session(meta):
        return True
    ids = {str(value) for value in (meta.get("id"), meta.get("parent_thread_id")) if value}
    if excluded_ids & ids:
        return True
    return any(excluded_id in path.name for excluded_id in excluded_ids)


def iter_session_files(
    roots: list[Path],
    days: int,
    min_size: int,
    excluded_ids: set[str],
    include_subagents: bool,
) -> list[Path]:
    cutoff = time.time() - days * 86400
    rows: list[tuple[float, int, Path]] = []
    for root in roots:
        for path in root.rglob("*.jsonl"):
            if "/subagents/" in str(path) and not include_subagents:
                continue
            try:
                stat = path.stat()
            except OSError:
                continue
            if stat.st_mtime >= cutoff and stat.st_size >= min_size:
                meta = session_meta(path)
                if should_exclude_session(path, meta, excluded_ids, include_subagents):
                    continue
                rows.append((stat.st_mtime, stat.st_size, path))
    return [path for _, _, path in sorted(rows, reverse=True)]


def text_blocks(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for block in content:
        if isinstance(block, str):
            parts.append(block)
            continue
        if not isinstance(block, dict):
            continue
        block_type = block.get("type")
        if block_type and block_type not in TEXT_BLOCK_TYPES:
            continue
        text = block.get("text") or block.get("content")
        if isinstance(text, str):
            parts.append(text)
    return " ".join(parts).strip()


def is_injected_user_text(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return True
    if stripped.startswith(INJECTED_PREFIXES):
        return True
    return False


def parse_args_payload(arguments: Any) -> dict[str, Any]:
    if isinstance(arguments, dict):
        return arguments
    if not isinstance(arguments, str):
        return {}
    try:
        obj = json.loads(arguments)
    except json.JSONDecodeError:
        return {}
    return obj if isinstance(obj, dict) else {}


def stringify_arguments(arguments: Any) -> str:
    if isinstance(arguments, str):
        try:
            decoded = json.loads(arguments)
        except json.JSONDecodeError:
            return arguments
        if isinstance(decoded, str):
            return decoded
        return json.dumps(decoded, sort_keys=True)
    if arguments is None:
        return ""
    return json.dumps(arguments, sort_keys=True)


def command_prefix(cmd: str) -> str:
    first = cmd.strip().splitlines()[0].strip() if cmd.strip() else ""
    if not first:
        return ""
    try:
        tokens = shlex.split(first)
    except ValueError:
        tokens = first.split()
    return tokens[0] if tokens else ""


def interesting_path(raw: str) -> str | None:
    path = raw.rstrip("):,;\"'")
    if any(
        path.endswith(ext)
        for ext in (
            ".md",
            ".py",
            ".rs",
            ".toml",
            ".yaml",
            ".yml",
            ".json",
            ".sh",
            ".tsx",
            ".ts",
            ".jsx",
            ".js",
            ".html",
        )
    ):
        return path
    return None


def record_paths(raw: str, file_counts: Counter[str]) -> None:
    for match in PATH_RE.finditer(raw):
        if path_value := interesting_path(match.group(1)):
            file_counts[path_value] += 1


def record_patch_paths(raw: str, file_counts: Counter[str]) -> None:
    for match in re.finditer(r"\*\*\* (?:Update|Add|Delete) File: (.+)", raw):
        file_counts[match.group(1).strip()] += 1


def record_file_input(input_obj: Any, file_counts: Counter[str]) -> None:
    if not isinstance(input_obj, dict):
        return
    for key in ("file_path", "path"):
        value = input_obj.get(key)
        if isinstance(value, str):
            file_counts[value] += 1
    raw = json.dumps(input_obj, sort_keys=True)
    record_paths(raw, file_counts)


def bounded(items: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    return items[:limit]


def stability(count: int) -> str:
    if count >= 5:
        return "crystallized"
    if count >= 3:
        return "stable"
    if count >= 2:
        return "emerging"
    return "single"


def analyze_file(path: Path) -> dict[str, Any]:
    sid = path.name
    real_user_turns: list[dict[str, Any]] = []
    filtered_user_messages = 0
    all_real_text: list[str] = []
    command_lines: list[str] = []
    tool_text_snippets: list[str] = []
    tool_counts: Counter[str] = Counter()
    command_counts: Counter[str] = Counter()
    file_counts: Counter[str] = Counter()
    skill_mentions: Counter[str] = Counter()
    corrections: list[dict[str, Any]] = []
    subagent_notifications = 0

    def record_user_text(text: str) -> None:
        nonlocal filtered_user_messages, subagent_notifications
        if text.strip().startswith("<subagent_notification>"):
            subagent_notifications += 1
        if is_injected_user_text(text):
            filtered_user_messages += 1
            return
        turn_index = len(real_user_turns) + 1
        compact = " ".join(text.split())
        real_user_turns.append({"turn": turn_index, "text": compact[:500]})
        all_real_text.append(compact)
        for match in SKILL_RE.finditer(compact):
            skill_mentions[match.group(1)] += 1
        if CORRECTION_RE.search(compact):
            corrections.append(
                {
                    "session": sid,
                    "turn": turn_index,
                    "score": 2 if STRONG_CORRECTION_RE.search(compact) else 1,
                    "text": compact[:300],
                }
            )

    def record_tool(name: str, input_obj: Any, raw_text: str, count_patch_paths: bool = True) -> None:
        tool_counts[name] += 1
        tool_text_snippets.append(f"{name} {raw_text[:2000]}")
        if name in SUBAGENT_TOOL_NAMES:
            return
        if name.endswith("exec_command") or name == "exec_command" or name == "Bash":
            if isinstance(input_obj, dict):
                cmd = str(input_obj.get("cmd") or input_obj.get("command") or "")
            else:
                cmd = ""
            if cmd:
                command_lines.append(cmd)
                prefix = command_prefix(cmd)
                if prefix:
                    command_counts[prefix] += 1
                record_paths(cmd, file_counts)
        elif count_patch_paths and (name.endswith("apply_patch") or name == "apply_patch"):
            record_patch_paths(raw_text, file_counts)
        elif name in {"Edit", "MultiEdit", "Write", "NotebookEdit"}:
            record_file_input(input_obj, file_counts)

    with path.open(errors="ignore") as handle:
        for line in handle:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            obj_type = obj.get("type")
            if obj_type == "event_msg":
                payload = obj.get("payload")
                if not isinstance(payload, dict) or payload.get("type") != "patch_apply_end":
                    continue
                changes = payload.get("changes")
                if isinstance(changes, dict):
                    for changed_path in changes:
                        file_counts[str(changed_path)] += 1
                continue

            if obj_type == "user":
                message = obj.get("message")
                if isinstance(message, dict) and message.get("role") == "user":
                    record_user_text(text_blocks(message.get("content")))
                continue

            if obj_type == "assistant":
                message = obj.get("message")
                content = message.get("content") if isinstance(message, dict) else None
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_use":
                        continue
                    name = str(block.get("name") or "")
                    input_obj = block.get("input")
                    record_tool(name, input_obj, stringify_arguments(input_obj))
                continue

            if obj_type != "response_item":
                continue
            payload = obj.get("payload")
            if not isinstance(payload, dict):
                continue
            payload_type = payload.get("type")

            if payload_type == "message":
                role = payload.get("role")
                text = text_blocks(payload.get("content"))
                if role == "user":
                    record_user_text(text)
                continue

            if payload_type == "custom_tool_call":
                name = str(payload.get("name") or "")
                raw_text = str(payload.get("input") or "")
                record_tool(name, {}, raw_text, count_patch_paths=False)
                continue

            if payload_type != "function_call":
                continue
            name = str(payload.get("name") or "")
            raw_arguments = payload.get("arguments")
            arguments = parse_args_payload(raw_arguments)
            arg_text = stringify_arguments(raw_arguments)
            record_tool(name, arguments, arg_text)

    joined = "\n".join(all_real_text + command_lines + tool_text_snippets)
    patterns = [name for name, _, regex in PATTERNS if regex.search(joined)]
    preamble = [turn["text"][:220] for turn in real_user_turns[:3]]
    return {
        "session": sid,
        "path": str(path),
        "real_user_turns": real_user_turns,
        "filtered_user_messages": filtered_user_messages,
        "corrections": corrections,
        "tool_counts": dict(tool_counts),
        "command_counts": dict(command_counts),
        "file_counts": dict(file_counts),
        "skill_mentions": dict(skill_mentions),
        "patterns": patterns,
        "preamble": preamble,
        "subagent_notifications": subagent_notifications,
    }


def counter_rows(counter: Counter[str], limit: int) -> list[dict[str, Any]]:
    return [{"name": name, "count": count} for name, count in counter.most_common(limit)]


def aggregate(files: list[Path], max_corrections: int) -> dict[str, Any]:
    sessions = [analyze_file(path) for path in files]
    tool_counts: Counter[str] = Counter()
    command_counts: Counter[str] = Counter()
    file_counts: Counter[str] = Counter()
    skill_mentions: Counter[str] = Counter()
    tool_sessions: dict[str, set[str]] = defaultdict(set)
    pattern_sessions: dict[str, set[str]] = defaultdict(set)
    pattern_examples: dict[str, list[str]] = defaultdict(list)
    corrections: list[dict[str, Any]] = []
    preambles: list[dict[str, Any]] = []
    filtered = 0
    subagent_notifications = 0

    for session in sessions:
        sid = session["session"]
        filtered += int(session["filtered_user_messages"])
        subagent_notifications += int(session["subagent_notifications"])
        tool_counts.update(session["tool_counts"])
        command_counts.update(session["command_counts"])
        file_counts.update(session["file_counts"])
        skill_mentions.update(session["skill_mentions"])
        corrections.extend(session["corrections"])
        if session["preamble"]:
            preambles.append({"session": sid, "turns": session["preamble"]})
        for tool in session["tool_counts"]:
            tool_sessions[tool].add(sid)
        for pattern in session["patterns"]:
            pattern_sessions[pattern].add(sid)
            if len(pattern_examples[pattern]) < 3 and session["preamble"]:
                pattern_examples[pattern].append(f"{sid}: {session['preamble'][0][:160]}")

    corrections.sort(key=lambda row: (row["score"], row["session"], row["turn"]), reverse=True)
    pattern_descriptions = {name: desc for name, desc, _ in PATTERNS}
    patterns = []
    for name, sids in sorted(pattern_sessions.items(), key=lambda item: (-len(item[1]), item[0])):
        count = len(sids)
        patterns.append(
            {
                "name": name,
                "description": pattern_descriptions[name],
                "sessions": count,
                "stability": stability(count),
                "examples": pattern_examples[name],
            }
        )

    candidate_gaps = [
        {
            "pattern": row["name"],
            "status": "candidate",
            "reason": f"{row['stability']} pattern in {row['sessions']} sampled sessions; verify against scaffold before editing",
        }
        for row in patterns
        if row["sessions"] >= 2
    ]

    top_tools = []
    for row in counter_rows(tool_counts, 20):
        top_tools.append({**row, "sessions": len(tool_sessions[row["name"]])})

    return {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sampled_sessions": [{"session": p.name, "path": str(p)} for p in files],
        "sample_count": len(files),
        "filtered_user_messages": filtered,
        "subagent_notifications_filtered": subagent_notifications,
        "correction_candidates": bounded(corrections, max_corrections),
        "top_tools": top_tools,
        "top_commands": counter_rows(command_counts, 20),
        "top_files": counter_rows(file_counts, 25),
        "skill_mentions": counter_rows(skill_mentions, 20),
        "workflow_patterns": patterns,
        "candidate_scaffold_gaps": candidate_gaps,
        "recent_preambles": preambles[:12],
    }


def markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Scaffold Signals",
        "",
        f"- Generated: `{report['generated_at']}`",
        f"- Sampled sessions: `{report['sample_count']}`",
        f"- Filtered injected user messages: `{report['filtered_user_messages']}`",
        f"- Filtered subagent notifications: `{report['subagent_notifications_filtered']}`",
        "",
        "## Correction Candidates",
    ]
    for row in report["correction_candidates"][:20]:
        text = row["text"].replace("|", "\\|")
        lines.append(f"- `{row['session']}` turn {row['turn']} score={row['score']}: {text}")

    lines.extend(["", "## Workflow Patterns"])
    for row in report["workflow_patterns"]:
        lines.append(
            f"- `{row['name']}`: {row['sessions']} sessions, {row['stability']} - {row['description']}"
        )

    lines.extend(["", "## Top Tools"])
    for row in report["top_tools"][:15]:
        lines.append(f"- `{row['name']}`: {row['count']} calls across {row['sessions']} sessions")

    lines.extend(["", "## Top Commands"])
    for row in report["top_commands"][:15]:
        lines.append(f"- `{row['name']}`: {row['count']}")

    lines.extend(["", "## Top Files"])
    for row in report["top_files"][:15]:
        lines.append(f"- `{row['name']}`: {row['count']}")

    lines.extend(["", "## Candidate Scaffold Gaps"])
    for row in report["candidate_scaffold_gaps"]:
        lines.append(f"- `{row['pattern']}`: {row['reason']}")

    lines.extend(["", "## Recent Preambles"])
    for row in report["recent_preambles"]:
        lines.append(f"- `{row['session']}`")
        for turn in row["turns"]:
            lines.append(f"  - {turn}")

    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-home", type=Path)
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--max-sessions", type=int, default=20)
    parser.add_argument("--min-size", type=int, default=10_000)
    parser.add_argument("--max-corrections", type=int, default=40)
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--exclude-session",
        action="append",
        default=[],
        help="Session/thread id or filename fragment to exclude; CODEX_THREAD_ID is excluded by default.",
    )
    parser.add_argument(
        "--include-current",
        action="store_true",
        help="Do not automatically exclude CODEX_THREAD_ID.",
    )
    parser.add_argument(
        "--include-subagents",
        action="store_true",
        help="Include sessions whose metadata marks them as subagent-created.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    agent_home = args.agent_home.expanduser() if args.agent_home else resolve_agent_home()
    excluded_ids = set(args.exclude_session)
    if not args.include_current:
        excluded_ids = exclude_current_ids(args.exclude_session)
    files = iter_session_files(
        session_roots(agent_home),
        args.days,
        args.min_size,
        excluded_ids,
        args.include_subagents,
    )[: args.max_sessions]
    report = aggregate(files, args.max_corrections)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n" if args.format == "json" else markdown(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
