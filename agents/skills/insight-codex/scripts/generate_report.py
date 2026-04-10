#!/usr/bin/env python3
"""Generate a shareable HTML usage report from local Codex session logs."""

from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
import shlex
from collections import Counter
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


INSTRUCTION_PREFIXES = (
    "# AGENTS.md instructions",
    "<environment_context>",
)

CORRECTION_PATTERNS = (
    re.compile(r"\bi meant\b"),
    re.compile(r"\bactually\b"),
    re.compile(r"\bthat(?:'| i)?s not\b"),
    re.compile(r"\bwrong\b"),
    re.compile(r"\binstead\b"),
    re.compile(r"\bwait\b"),
    re.compile(r"\bstop\b"),
    re.compile(r"\bdon't\b"),
    re.compile(r"\bdo not\b"),
    re.compile(r"\bno[, ]"),
)

EXIT_CODE_RE = re.compile(r"Process exited with code (\d+)")
PATH_SUFFIX_RE = re.compile(
    r"(?P<path>(?:~|/)[^\s\"']+\.(?:rs|py|ts|tsx|js|jsx|md|sh|toml|yaml|yml|json|html|css|sql))"
)
GOOD_TOOL_NAMES = re.compile(r"^[A-Za-z0-9_:.+-]{1,80}$")

REPO_LABELS = {
    "aiperf": "aiperf",
    "codex": "Codex",
    "claw-code": "Claw Code",
    "dotfiles": "Dotfiles",
    "dfile": "dfile",
    "dynamo": "Dynamo",
    "memory": "Memory",
    "modelexpress": "ModelExpress",
    "opencode": "OpenCode",
    "sglang": "SGLang",
    "sglang-main": "SGLang",
    "sglang-retention": "SGLang retention",
    "thunderagent": "ThunderAgent",
}

GENERIC_REPOS = {"ephemeral", "home", "unknown", "ubuntu"}

WORK_AREA_DEFS = (
    {
        "key": "codex-runtime",
        "label": "Codex / OpenCode Agent Runtime",
        "repos": {"codex", "opencode", "claw-code"},
        "base_desc": "Work on the agent runtime itself: provider integration, cleanup, review loops, harness behavior, and longer-form maintenance inside the Codex/OpenCode stack.",
    },
    {
        "key": "distributed-serving",
        "label": "Dynamo / Distributed Serving",
        "repos": {"dynamo", "modelexpress"},
        "base_desc": "Core serving work around Dynamo and adjacent infra: PR handling, provider integration, debugging, merge resolution, and performance-oriented systems work.",
    },
    {
        "key": "sglang-systems",
        "label": "SGLang Cache / Session Systems",
        "repos": {"sglang", "sglang-main", "sglang-retention"},
        "base_desc": "Session, cache, and runtime work in the SGLang family, including review-driven fixes, merge work, regression checks, and system-level debugging.",
    },
    {
        "key": "benchmarking",
        "label": "Benchmarking / Trace Tooling",
        "repos": {"aiperf", "traces", "bench_results", "calc"},
        "base_desc": "Benchmark harnesses, trace preparation, and performance experiments used to reason about agentic workloads and serving behavior.",
    },
    {
        "key": "scaffold",
        "label": "Scaffold / Memory / Meta Tooling",
        "repos": {"dotfiles", "memory", "home", "ephemeral", "logs", "dfile"},
        "base_desc": "Work on the surrounding agent scaffold itself: instructions, memory, tooling, reporting, and repo-orientation mechanics.",
    },
)

FRICTION_INFO = {
    "wrong_approach": {
        "title": "Wrong Initial Approach Requiring Course Corrections",
        "desc": "The logs show sessions where Codex needed redirection after heading down the wrong code path or abstraction level. A short plan-first checkpoint would likely reduce that churn.",
    },
    "validation_gap": {
        "title": "Validation and Push-Fix Loops",
        "desc": "Commit and push heavy sessions still accumulate build, test, git, and GitHub failures. That usually means the validation loop is happening after a write, not before it.",
    },
    "environment_friction": {
        "title": "Tooling and Environment Friction",
        "desc": "A noticeable share of non-zero exits comes from shell orchestration, setup, process control, or connector usage rather than from the core code change itself.",
    },
    "long_iteration_loop": {
        "title": "Long Iteration Loops",
        "desc": "Some sessions stretch into long churn cycles with lots of command failures before landing. Those are good candidates for stronger workflow scaffolding or more aggressive checkpoints.",
    },
}

GIT_COMMIT_CMD_RE = re.compile(r"(^|&&|;|\|\||\n)\s*git\s+commit\b")
GIT_PUSH_CMD_RE = re.compile(r"(^|&&|;|\|\||\n)\s*git\s+push\b")
GH_CMD_RE = re.compile(r"(^|&&|;|\|\||\n)\s*gh\b")
HOME_DIR = Path.home().resolve()


@dataclass
class SessionSummary:
    session_id: str
    output_key: str
    source_file: str
    start_time: str
    end_time: str
    cwd: str
    repo: str
    duration_minutes: int
    user_message_count: int
    assistant_message_count: int
    commentary_count: int
    final_count: int
    first_prompt: str
    tool_counts: dict[str, int]
    command_prefixes: dict[str, int]
    failed_command_prefixes: dict[str, int]
    git_commits: int
    git_pushes: int
    github_cli_commands: int
    input_tokens: int
    cached_input_tokens: int
    output_tokens: int
    reasoning_output_tokens: int
    peak_total_tokens: int
    tool_errors: int
    correction_signals: int
    uses_subagents: bool
    uses_github_app: bool
    uses_update_plan: bool
    touched_extensions: dict[str, int]
    brief_summary: str


@dataclass
class EnrichedSession:
    session: SessionSummary
    goal_categories: dict[str, int]
    friction_counts: dict[str, int]
    friction_detail: str
    outcome: str
    session_type: str
    primary_success: str


@dataclass
class SessionState:
    path: Path
    session_id: str = ""
    cwd: str = ""
    start_ts: datetime | None = None
    end_ts: datetime | None = None
    user_messages: list[str] = field(default_factory=list)
    assistant_messages: int = 0
    commentary_count: int = 0
    final_count: int = 0
    tool_counts: Counter[str] = field(default_factory=Counter)
    command_prefixes: Counter[str] = field(default_factory=Counter)
    failed_command_prefixes: Counter[str] = field(default_factory=Counter)
    git_commits: int = 0
    git_pushes: int = 0
    github_cli_commands: int = 0
    input_tokens: int = 0
    cached_input_tokens: int = 0
    output_tokens: int = 0
    reasoning_output_tokens: int = 0
    peak_total_tokens: int = 0
    tool_errors: int = 0
    correction_signals: int = 0
    uses_subagents: bool = False
    uses_github_app: bool = False
    uses_update_plan: bool = False
    touched_extensions: Counter[str] = field(default_factory=Counter)
    call_prefixes: dict[str, str] = field(default_factory=dict)
    workdir_roots: Counter[str] = field(default_factory=Counter)

    def absorb_timestamp(self, raw_ts: str | None) -> None:
        if not raw_ts:
            return
        current = parse_timestamp(raw_ts)
        if self.start_ts is None or current < self.start_ts:
            self.start_ts = current
        if self.end_ts is None or current > self.end_ts:
            self.end_ts = current

    def real_user_messages(self) -> list[str]:
        return [text for text in self.user_messages if is_real_user_message(text)]

    def build_summary(self) -> SessionSummary | None:
        real_messages = self.real_user_messages()
        if not self.session_id:
            self.session_id = self.path.stem.split("-")[-1]
        if self.start_ts is None:
            return None
        if self.end_ts is None:
            self.end_ts = self.start_ts
        cwd_repo = repo_key_from_cwd(self.cwd)
        repo = cwd_repo
        for candidate, _ in self.workdir_roots.most_common():
            if candidate not in GENERIC_REPOS:
                if cwd_repo in GENERIC_REPOS or self.workdir_roots[candidate] >= self.workdir_roots[cwd_repo]:
                    repo = candidate
                    break
        duration_minutes = max(1, int(round((self.end_ts - self.start_ts).total_seconds() / 60.0)))
        first_prompt = clean_text(real_messages[0]) if real_messages else "(no prompt found)"
        top_commands = ", ".join(
            f"{name} x{count}" for name, count in self.command_prefixes.most_common(3)
        ) or "no shell commands"
        brief_summary = (
            f"{display_repo_name(repo)} for {duration_minutes}m, "
            f"{len(real_messages)} user turns, {self.tool_counts.get('exec_command', 0)} shell calls, "
            f"top commands: {top_commands}."
        )
        return SessionSummary(
            session_id=self.session_id,
            output_key=output_key_for_path(self.path),
            source_file=str(self.path),
            start_time=self.start_ts.isoformat(),
            end_time=self.end_ts.isoformat(),
            cwd=self.cwd,
            repo=repo,
            duration_minutes=duration_minutes,
            user_message_count=len(real_messages),
            assistant_message_count=self.assistant_messages,
            commentary_count=self.commentary_count,
            final_count=self.final_count,
            first_prompt=first_prompt,
            tool_counts=dict(self.tool_counts.most_common()),
            command_prefixes=dict(self.command_prefixes.most_common()),
            failed_command_prefixes=dict(self.failed_command_prefixes.most_common()),
            git_commits=self.git_commits,
            git_pushes=self.git_pushes,
            github_cli_commands=self.github_cli_commands,
            input_tokens=self.input_tokens,
            cached_input_tokens=self.cached_input_tokens,
            output_tokens=self.output_tokens,
            reasoning_output_tokens=self.reasoning_output_tokens,
            peak_total_tokens=self.peak_total_tokens,
            tool_errors=self.tool_errors,
            correction_signals=self.correction_signals,
            uses_subagents=self.uses_subagents,
            uses_github_app=self.uses_github_app,
            uses_update_plan=self.uses_update_plan,
            touched_extensions=dict(self.touched_extensions.most_common()),
            brief_summary=brief_summary,
        )


def codex_home() -> Path:
    raw = os.environ.get("CODEX_HOME")
    if raw:
        return Path(raw).expanduser()
    script_path = Path(__file__).resolve()
    for parent in script_path.parents:
        if parent.name == "skills" and (parent.parent / "sessions").exists():
            return parent.parent
    return Path.home() / ".codex"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sessions-root",
        default=None,
        help="Root directory containing Codex session JSONL files. Defaults to <codex-home>/sessions.",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory for report.html, session-meta/, and facets/. Defaults to <codex-home>/usage-data.",
    )
    parser.add_argument(
        "--codex-home",
        default=None,
        help="Codex home used to derive default input and output locations.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="Only analyze sessions modified within the last N days.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only analyze the most recent N session files after filtering.",
    )
    return parser.parse_args()


def parse_timestamp(raw: str) -> datetime:
    return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(timezone.utc)


def clean_text(text: str, limit: int = 220) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def is_real_user_message(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return False
    return not any(stripped.startswith(prefix) for prefix in INSTRUCTION_PREFIXES)


def repo_key_from_cwd(cwd: str) -> str:
    path = Path(cwd).expanduser().resolve(strict=False)
    parts = path.parts
    home_parts = HOME_DIR.parts
    if path == HOME_DIR:
        return "home"
    if str(path) == "/ephemeral":
        return "ephemeral"
    if len(parts) >= 3 and parts[1] == "ephemeral":
        return parts[2].lower()
    if len(parts) > len(home_parts) and parts[: len(home_parts)] == home_parts:
        return parts[len(home_parts)].lower()
    if parts:
        return parts[-1].lower()
    return "unknown"


def display_repo_name(repo: str) -> str:
    return REPO_LABELS.get(repo, repo.replace("-", " "))


def output_key_for_path(path: Path) -> str:
    parts = list(path.parts[-4:])
    key = "__".join(parts)
    return key.replace(".jsonl", "").replace("/", "__")


def safe_tool_name(name: str) -> bool:
    return bool(name and GOOD_TOOL_NAMES.match(name))


def extract_prompt_text(content: list[dict[str, Any]]) -> str:
    parts = []
    for block in content:
        block_type = block.get("type")
        if block_type in {"input_text", "output_text"} and block.get("text"):
            parts.append(block["text"])
    return "\n".join(parts).strip()


def extract_command_prefix(cmd: str) -> str:
    first_line = ""
    for line in cmd.splitlines():
        stripped = line.strip()
        if stripped:
            first_line = stripped
            break
    if not first_line:
        return "(empty)"
    segments = re.split(r"\s*(?:&&|\|\||;)\s*", first_line)
    for segment in segments:
        segment = segment.strip()
        if not segment:
            continue
        try:
            tokens = shlex.split(segment)
        except ValueError:
            tokens = segment.split()
        if not tokens:
            continue
        index = 0
        while index < len(tokens) and tokens[index] in {"env", "command", "time", "sudo"}:
            index += 1
        if index >= len(tokens):
            continue
        name = Path(tokens[index]).name
        if name in {"cd", "export", "set"}:
            continue
        return name
    return "(shell)"


def find_touched_extensions(text: str) -> Counter[str]:
    counts: Counter[str] = Counter()
    for match in PATH_SUFFIX_RE.finditer(text):
        suffix = Path(match.group("path")).suffix.lower()
        if suffix:
            counts[suffix] += 1
    return counts


def analyze_session(path: Path) -> SessionSummary | None:
    state = SessionState(path=path)
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            state.absorb_timestamp(item.get("timestamp"))
            item_type = item.get("type")
            payload = item.get("payload", {})
            if item_type == "session_meta":
                state.session_id = payload.get("id", state.session_id)
                state.cwd = payload.get("cwd", state.cwd)
                state.absorb_timestamp(payload.get("timestamp"))
                continue
            if item_type == "turn_context":
                state.cwd = payload.get("cwd", state.cwd)
                continue
            if item_type == "event_msg" and payload.get("type") == "token_count":
                info = payload.get("info") or {}
                last_usage = info.get("last_token_usage", {})
                total_usage = info.get("total_token_usage", {})
                state.input_tokens += int(last_usage.get("input_tokens", 0))
                state.cached_input_tokens += int(last_usage.get("cached_input_tokens", 0))
                state.output_tokens += int(last_usage.get("output_tokens", 0))
                state.reasoning_output_tokens += int(last_usage.get("reasoning_output_tokens", 0))
                state.peak_total_tokens = max(
                    state.peak_total_tokens,
                    int(total_usage.get("total_tokens", 0)),
                )
                continue
            if item_type != "response_item":
                continue
            payload_type = payload.get("type")
            if payload_type == "message":
                role = payload.get("role")
                if role == "user":
                    text = extract_prompt_text(payload.get("content", []))
                    if text:
                        state.user_messages.append(text)
                        real_messages = state.real_user_messages()
                        if real_messages and len(text) < 500:
                            lowered = text.lower()
                            if any(pattern.search(lowered) for pattern in CORRECTION_PATTERNS):
                                state.correction_signals += 1
                elif role == "assistant":
                    state.assistant_messages += 1
                    phase = payload.get("phase")
                    if phase == "commentary":
                        state.commentary_count += 1
                    elif phase in {"final", "final_answer"}:
                        state.final_count += 1
                continue
            if payload_type == "function_call":
                name = payload.get("name", "")
                if safe_tool_name(name):
                    state.tool_counts[name] += 1
                call_id = payload.get("call_id")
                if name == "spawn_agent":
                    state.uses_subagents = True
                if name.startswith("mcp__codex_apps__github_"):
                    state.uses_github_app = True
                if name == "update_plan":
                    state.uses_update_plan = True
                if name == "exec_command":
                    try:
                        args = json.loads(payload.get("arguments", "{}"))
                    except json.JSONDecodeError:
                        args = {}
                    cmd = args.get("cmd", "")
                    workdir = args.get("workdir")
                    if workdir:
                        state.workdir_roots[repo_key_from_cwd(workdir)] += 1
                    prefix = extract_command_prefix(cmd)
                    state.command_prefixes[prefix] += 1
                    state.touched_extensions.update(find_touched_extensions(cmd))
                    if call_id:
                        state.call_prefixes[call_id] = prefix
                    if GIT_COMMIT_CMD_RE.search(cmd):
                        state.git_commits += 1
                    if GIT_PUSH_CMD_RE.search(cmd):
                        state.git_pushes += 1
                    if GH_CMD_RE.search(cmd):
                        state.github_cli_commands += 1
                else:
                    if call_id:
                        state.call_prefixes[call_id] = name
                continue
            if payload_type == "function_call_output":
                output = payload.get("output", "")
                state.touched_extensions.update(find_touched_extensions(output))
                match = EXIT_CODE_RE.search(output)
                if match and int(match.group(1)) != 0:
                    state.tool_errors += 1
                    prefix = state.call_prefixes.get(payload.get("call_id", ""), "(unknown)")
                    state.failed_command_prefixes[prefix] += 1
                continue
    return state.build_summary()


def join_labels(labels: list[str]) -> str:
    if not labels:
        return "general engineering work"
    if len(labels) == 1:
        return labels[0]
    if len(labels) == 2:
        return f"{labels[0]} and {labels[1]}"
    return f"{', '.join(labels[:-1])}, and {labels[-1]}"


def top_items(mapping: dict[str, int], limit: int = 3) -> list[str]:
    return [name for name, _ in Counter(mapping).most_common(limit)]


def summarize_failures(failed: dict[str, int], limit: int = 3) -> str:
    parts = [f"{name} x{count}" for name, count in Counter(failed).most_common(limit)]
    return ", ".join(parts) if parts else "none"


def infer_goal_categories(session: SessionSummary) -> Counter[str]:
    prompt = session.first_prompt.lower()
    commands = set(session.command_prefixes)
    categories: Counter[str] = Counter()

    if session.git_commits or session.git_pushes or any(
        token in prompt for token in ("git ", "branch", "fork", "push", "commit")
    ):
        categories["Git Operations"] += 1
    if session.git_pushes or "push" in prompt:
        categories["Git Push"] += 1
    if any(token in prompt for token in ("merge conflict", "merge conflicts", "rebase", "resolve conflicts")):
        categories["Merge Conflict Resolution"] += 1
    if session.github_cli_commands or any(
        token in prompt
        for token in ("pr review", "review comments", "review comment", "requested changes", "/review", "latest comments")
    ):
        categories["Code Review"] += 1
    if any(token in prompt for token in ("implement", "add support", "support for", "build ", "create ", "wire up")):
        categories["Feature Implementation"] += 1
    if any(token in prompt for token in ("fix ", "debug", "bug", "regression", "failing", "error", "panic")):
        categories["Bug Fix"] += 1
    if any(token in prompt for token in ("benchmark", "perf", "performance", "throughput", "latency", "profile")):
        categories["Benchmarking"] += 1
    if any(token in prompt for token in ("blog", "docs", "documentation", "write", "rfc", "roadmap", "plan")):
        categories["Content Editing"] += 1
    if session.repo in {"dotfiles", "memory", "home", "ephemeral", "logs"} or any(
        token in prompt for token in ("skill", "scaffold", "insights", "memory", "claude.md", "agents.md")
    ):
        categories["Scaffold / Meta"] += 1
    if session.uses_subagents or any(
        token in prompt
        for token in ("ground yourself", "explain", "analyze", "investigate", "review overall", "where we are at")
    ):
        categories["Research / Planning"] += 1
    if "cargo" in commands or "pytest" in commands or "python" in commands or "python3" in commands:
        categories["Validation / Execution"] += 1

    if not categories:
        categories["General Engineering"] = 1
    return categories


def infer_friction_counts(session: SessionSummary) -> Counter[str]:
    failed = Counter(session.failed_command_prefixes)
    counts: Counter[str] = Counter()

    build_failures = sum(failed[name] for name in ("cargo", "pytest", "just", "maturin", "uv", "python", "python3"))
    git_failures = sum(failed[name] for name in ("git", "gh"))
    env_failures = sum(
        failed[name] for name in ("write_stdin", "source", "curl", "pkill", "ps", "sleep", "ss", "TOKEN=$(gh")
    )

    if session.correction_signals:
        counts["wrong_approach"] += session.correction_signals
    if (session.git_pushes or session.git_commits) and (build_failures or git_failures):
        counts["validation_gap"] += build_failures + git_failures
    if env_failures:
        counts["environment_friction"] += env_failures
    if session.duration_minutes >= 60 and session.tool_errors >= 12:
        counts["long_iteration_loop"] += max(1, session.tool_errors // 8)
    if not counts and session.tool_errors:
        counts["environment_friction"] += session.tool_errors
    return counts


def infer_outcome(session: SessionSummary, goals: Counter[str], friction: Counter[str]) -> str:
    shipping = session.git_commits + session.git_pushes
    if shipping >= 4 and session.tool_errors <= 15:
        return "achieved"
    if shipping >= 1 or session.final_count or "Feature Implementation" in goals or "Bug Fix" in goals:
        return "mostly_achieved"
    if sum(friction.values()) >= 12:
        return "partial_progress"
    return "unclear"


def infer_session_type(session: SessionSummary, goals: Counter[str]) -> str:
    if len(goals) >= 4:
        return "multi_task"
    if session.uses_subagents:
        return "delegated"
    if "Merge Conflict Resolution" in goals or "Git Operations" in goals or session.git_pushes:
        return "git_heavy"
    if "Bug Fix" in goals and session.tool_errors:
        return "debug_heavy"
    return "focused"


def infer_primary_success(session: SessionSummary, goals: Counter[str]) -> str:
    if session.git_commits or session.git_pushes:
        return "multi_file_changes"
    if "Bug Fix" in goals:
        return "good_debugging"
    if "Code Review" in goals:
        return "review_and_synthesis"
    if "Scaffold / Meta" in goals:
        return "tooling_scaffold"
    if "Content Editing" in goals:
        return "written_output"
    return "analysis_and_orientation"


def build_friction_detail(session: SessionSummary, friction: Counter[str]) -> str:
    if not friction:
        return ""
    dominant = friction.most_common(1)[0][0]
    if dominant == "wrong_approach":
        return "Course corrections dominated the friction signal in this session."
    if dominant == "validation_gap":
        return (
            f"Validation friction clustered around {summarize_failures(session.failed_command_prefixes)}, "
            "suggesting a push-fix loop."
        )
    if dominant == "environment_friction":
        return f"Most non-zero exits came from tooling and shell orchestration ({summarize_failures(session.failed_command_prefixes)})."
    return "The session accumulated a long iteration loop before stabilizing."


def enrich_session(session: SessionSummary) -> EnrichedSession:
    goals = infer_goal_categories(session)
    friction = infer_friction_counts(session)
    return EnrichedSession(
        session=session,
        goal_categories=dict(goals.most_common()),
        friction_counts=dict(friction.most_common()),
        friction_detail=build_friction_detail(session, friction),
        outcome=infer_outcome(session, goals, friction),
        session_type=infer_session_type(session, goals),
        primary_success=infer_primary_success(session, goals),
    )


def build_facets(session: SessionSummary) -> dict[str, Any]:
    enriched = enrich_session(session)
    top_tools = list(session.tool_counts.items())[:4]
    top_commands = list(session.command_prefixes.items())[:4]
    return {
        "session_id": session.session_id,
        "repo": session.repo,
        "repo_label": display_repo_name(session.repo),
        "underlying_goal": session.first_prompt,
        "goal_categories": enriched.goal_categories,
        "outcome": enriched.outcome,
        "session_type": enriched.session_type,
        "friction_counts": enriched.friction_counts,
        "friction_detail": enriched.friction_detail,
        "primary_success": enriched.primary_success,
        "top_tools": top_tools,
        "top_commands": top_commands,
        "friction": {
            "tool_errors": session.tool_errors,
            "correction_signals": session.correction_signals,
            "failed_command_prefixes": session.failed_command_prefixes,
        },
        "brief_summary": session.brief_summary,
        "first_prompt": session.first_prompt,
    }


def format_int(value: int) -> str:
    return f"{value:,}"


def format_duration(minutes: int) -> str:
    if minutes >= 60:
        hours = minutes / 60.0
        return f"{hours:.1f}h"
    return f"{minutes}m"


def format_tokens(value: int) -> str:
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return str(value)


def bar_rows(counter: Counter[str], palette: str, width: int = 6, limit: int = 6) -> str:
    if not counter:
        return '<div class="empty">No data</div>'
    top = counter.most_common(limit)
    ceiling = top[0][1] or 1
    rows = []
    for label, value in top:
        fill = max(width, int(math.ceil((value / ceiling) * 100)))
        rows.append(
            "<div class='bar-row'>"
            f"<div class='bar-label'>{html.escape(label)}</div>"
            f"<div class='bar-track'><div class='bar-fill' style='width:{fill}%;background:{palette}'></div></div>"
            f"<div class='bar-value'>{format_int(value)}</div>"
            "</div>"
        )
    return "".join(rows)


def render_glance_cards(stats: dict[str, Any]) -> str:
    return "".join(
        (
            "<div class='glance-card'>"
            f"<div class='glance-value'>{html.escape(stats['value'])}</div>"
            f"<div class='glance-label'>{html.escape(stats['label'])}</div>"
            f"<div class='glance-detail'>{html.escape(stats['detail'])}</div>"
            "</div>"
        )
        for stats in stats["cards"]
    )


def render_repo_cards(repo_counter: Counter[str], duration_by_repo: Counter[str]) -> str:
    preferred = [item for item in repo_counter.most_common() if item[0] not in GENERIC_REPOS]
    entries = preferred or repo_counter.most_common()
    cards = []
    for repo, count in entries[:6]:
        cards.append(
            "<div class='repo-card'>"
            f"<div class='repo-name'>{html.escape(display_repo_name(repo))}</div>"
            f"<div class='repo-meta'>{format_int(count)} sessions • {format_duration(duration_by_repo[repo])}</div>"
            "</div>"
        )
    return "".join(cards) or "<div class='empty'>No repository data</div>"


def pick_work_area(repo: str) -> dict[str, Any]:
    for area in WORK_AREA_DEFS:
        if repo in area["repos"]:
            return area
    return {
        "key": repo,
        "label": display_repo_name(repo),
        "repos": {repo},
        "base_desc": f"Sessions focused on {display_repo_name(repo)}.",
    }


def project_areas(enriched_sessions: list[EnrichedSession]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for enriched in enriched_sessions:
        area = pick_work_area(enriched.session.repo)
        bucket = grouped.setdefault(
            area["key"],
            {
                "label": area["label"],
                "base_desc": area["base_desc"],
                "sessions": [],
                "duration": 0,
            },
        )
        bucket["sessions"].append(enriched)
        bucket["duration"] += enriched.session.duration_minutes

    output = []
    for bucket in grouped.values():
        goal_counter: Counter[str] = Counter()
        command_counter: Counter[str] = Counter()
        for enriched in bucket["sessions"]:
            goal_counter.update(enriched.goal_categories)
            command_counter.update(enriched.session.command_prefixes)
        top_goals = [label.lower() for label, _ in goal_counter.most_common(2)]
        top_commands = top_items(dict(command_counter), 3)
        extra = ""
        if top_goals:
            extra = f" Recent sessions skewed toward {join_labels(top_goals)}."
        if top_commands:
            extra += f" Common shell loops used {join_labels(top_commands)}."
        output.append(
            {
                "label": bucket["label"],
                "count": len(bucket["sessions"]),
                "duration": bucket["duration"],
                "desc": bucket["base_desc"] + extra,
            }
        )
    return sorted(output, key=lambda item: item["duration"], reverse=True)


def usage_narrative(
    enriched_sessions: list[EnrichedSession],
    goal_counter: Counter[str],
    tool_counter: Counter[str],
    command_counter: Counter[str],
    duration_by_repo: Counter[str],
    total_commentary: int,
    total_final: int,
    delegated_sessions: int,
) -> list[str]:
    narrative_goals = Counter(goal_counter)
    if len(narrative_goals) > 2:
        narrative_goals.pop("Scaffold / Meta", None)
        narrative_goals.pop("General Engineering", None)
    top_goals = top_items(dict(narrative_goals or goal_counter), 3)
    top_commands = top_items(dict(command_counter), 4)
    top_repos = [
        display_repo_name(repo)
        for repo, _ in sorted(duration_by_repo.items(), key=lambda item: item[1], reverse=True)
        if repo not in GENERIC_REPOS
    ][:3]

    paragraph_one = (
        f"Your dominant Codex workflow is {join_labels([label.lower() for label in top_goals])}. "
        f"The heaviest work areas are {join_labels(top_repos)}, and the logs show that you lean on Codex as an operator inside those repos rather than as a one-shot code generator."
    )
    paragraph_two = (
        f"Shell execution dominates the corpus: `exec_command` appears {format_int(tool_counter.get('exec_command', 0))} times, "
        f"with {join_labels(top_commands)} forming the core loop. Commentary updates ({format_int(total_commentary)}) outnumber final answers ({format_int(total_final)}), "
        "which fits an interactive steer-and-correct style."
    )
    if delegated_sessions:
        paragraph_two += (
            f" Subagents show up in {format_int(delegated_sessions)} sessions, so parallel delegation is present, but still a secondary pattern compared with shell-forward work."
        )
    return [paragraph_one, paragraph_two]


def at_a_glance(
    goal_counter: Counter[str],
    friction_counter: Counter[str],
    duration_by_repo: Counter[str],
    total_errors: int,
    delegated_sessions: int,
    total_pushes: int,
    total_commits: int,
) -> dict[str, str]:
    narrative_goals = Counter(goal_counter)
    if len(narrative_goals) > 2:
        narrative_goals.pop("Scaffold / Meta", None)
        narrative_goals.pop("General Engineering", None)
    top_goals = [label.lower() for label in top_items(dict(narrative_goals or goal_counter), 3)]
    top_repos = [
        display_repo_name(repo)
        for repo, _ in sorted(duration_by_repo.items(), key=lambda item: item[1], reverse=True)
        if repo not in GENERIC_REPOS
    ][:3]
    dominant_friction = friction_counter.most_common(1)[0][0] if friction_counter else "environment_friction"

    working = (
        f"You’re using Codex as a serious systems-work partner across {join_labels(top_repos[:3])}, "
        f"with {join_labels(top_goals)} showing up repeatedly. The volume of shell work and the presence of {format_int(delegated_sessions)} delegated sessions suggest you’re comfortable driving it as an active operator."
    )

    if dominant_friction == "validation_gap":
        hindering = (
            f"The biggest drag is still validation churn: {format_int(total_commits)} commits and {format_int(total_pushes)} pushes coexist with {format_int(total_errors)} non-zero command exits, which points to fix-push-fix loops."
        )
    elif dominant_friction == "wrong_approach":
        hindering = (
            "The biggest drag is early-session misalignment. A portion of the corpus shows Codex needing course corrections before it converges on the right repo path or solution shape."
        )
    else:
        hindering = (
            f"The biggest drag is environment and tooling friction. The corpus still contains {format_int(total_errors)} non-zero exits, many of them from shell orchestration and connector work rather than the target code change."
        )

    quick_wins = (
        "Tighter kickoff prompts and a mandatory validation pass before push would likely buy the fastest improvement. The logs support both: plan-first behavior is still rare relative to shell volume, and validation failures remain visible in write-heavy sessions."
    )
    ambitious = (
        "The next step is workflow specialization: Codex should know when a session is a review loop, merge loop, benchmark loop, or scaffold-maintenance loop and switch prompts/checklists automatically instead of waiting for you to restate the pattern."
    )

    return {
        "working": working,
        "hindering": hindering,
        "quick_wins": quick_wins,
        "ambitious": ambitious,
    }


def win_score(enriched: EnrichedSession) -> float:
    session = enriched.session
    return (
        session.git_commits * 3
        + session.git_pushes * 4
        + session.duration_minutes / 45.0
        + session.tool_counts.get("exec_command", 0) / 40.0
        + (2 if session.uses_subagents else 0)
        - session.tool_errors / 25.0
    )


def build_big_wins(enriched_sessions: list[EnrichedSession]) -> list[dict[str, str]]:
    candidates = sorted(enriched_sessions, key=win_score, reverse=True)
    wins = []
    seen_repos: set[str] = set()
    for enriched in candidates:
        session = enriched.session
        if session.repo in GENERIC_REPOS:
            continue
        if session.repo in seen_repos and len(wins) >= 2:
            continue
        seen_repos.add(session.repo)
        if session.git_pushes >= 3 or session.git_commits >= 4:
            title = f"Drove a heavy ship-and-validate loop in {display_repo_name(session.repo)}"
        elif session.uses_subagents:
            title = f"Used delegation to keep {display_repo_name(session.repo)} moving"
        elif "Bug Fix" in enriched.goal_categories:
            title = f"Pushed through a thorny debug loop in {display_repo_name(session.repo)}"
        else:
            title = f"Stayed with a long-form cleanup in {display_repo_name(session.repo)}"
        desc = (
            f"In one {format_duration(session.duration_minutes)} session, you ran {format_int(session.tool_counts.get('exec_command', 0))} shell commands, "
            f"made {format_int(session.git_commits)} commits and {format_int(session.git_pushes)} pushes, and kept the work grounded in: "
            f"{clean_text(session.first_prompt, 180)}"
        )
        wins.append({"title": title, "desc": desc})
        if len(wins) == 3:
            break
    return wins


def friction_example(enriched: EnrichedSession) -> str:
    session = enriched.session
    base = f"{display_repo_name(session.repo)} ({format_duration(session.duration_minutes)}): {clean_text(session.first_prompt, 150)}"
    if session.failed_command_prefixes:
        base += f" Failed prefixes: {summarize_failures(session.failed_command_prefixes)}."
    return base


def build_friction_sections(enriched_sessions: list[EnrichedSession]) -> list[dict[str, Any]]:
    totals: Counter[str] = Counter()
    by_category: dict[str, list[tuple[int, EnrichedSession]]] = {key: [] for key in FRICTION_INFO}
    for enriched in enriched_sessions:
        for category, count in enriched.friction_counts.items():
            totals[category] += count
            by_category.setdefault(category, []).append((count, enriched))

    sections = []
    for category, total in totals.most_common():
        if total <= 0 or category not in FRICTION_INFO:
            continue
        examples = [
            friction_example(enriched)
            for _, enriched in sorted(by_category[category], key=lambda item: item[0], reverse=True)[:2]
        ]
        sections.append(
            {
                "title": FRICTION_INFO[category]["title"],
                "desc": FRICTION_INFO[category]["desc"],
                "examples": examples,
            }
        )
        if len(sections) == 4:
            break
    return sections


def build_feature_cards(
    total_errors: int,
    total_pushes: int,
    total_commits: int,
    total_corrections: int,
    delegated_sessions: int,
) -> list[dict[str, str]]:
    return [
        {
            "title": "Pre-push validation gate",
            "oneliner": "Have Codex run the whole local validation stack before any push.",
            "why": (
                f"The corpus contains {format_int(total_commits)} commits, {format_int(total_pushes)} pushes, and {format_int(total_errors)} non-zero exits. "
                "That is exactly the profile where an explicit build/test gate pays off."
            ),
            "prompt": (
                "Before pushing anything, run the full local validation loop for this repo. Fix every failing check, rerun the full suite, and only then prepare the push summary."
            ),
        },
        {
            "title": "Plan-first reconnaissance",
            "oneliner": "Force a short orientation pass before edits when the task looks multi-step.",
            "why": (
                f"Correction-style turns appeared {format_int(total_corrections)} times. "
                "A lightweight map-the-codebase-first step would likely cut down wrong-path exploration."
            ),
            "prompt": (
                "Before making changes, map the relevant files, recent git history, and validation path. Give me a 3-bullet plan and wait for approval before editing."
            ),
        },
        {
            "title": "Workflow macros for repeated session types",
            "oneliner": "Start sessions with a repo-aware checklist instead of free-form context rebuilding.",
            "why": (
                f"Delegation showed up in {format_int(delegated_sessions)} sessions, but most work is still driven through repeated shell choreography. "
                "Codifying merge, review, benchmark, and scaffold-maintenance starts would remove setup overhead."
            ),
            "prompt": (
                "Treat this as a [review|merge|benchmark|scaffold] session. Load the relevant project memory, inspect git/worktree state, identify the validation loop, and then propose the narrowest path forward."
            ),
        },
    ]


def build_pattern_cards(
    goal_counter: Counter[str],
    command_counter: Counter[str],
    repo_counter: Counter[str],
) -> list[dict[str, str]]:
    top_repos = [display_repo_name(repo) for repo, _ in repo_counter.most_common(3) if repo not in GENERIC_REPOS]
    return [
        {
            "title": "Terminal-first operator mode",
            "summary": "You use Codex more like a shell-forward operator than a pure text editor.",
            "detail": (
                f"The dominant command prefixes are {join_labels(top_items(dict(command_counter), 4))}, which means most value is being extracted through repo inspection, build/test loops, and command orchestration."
            ),
            "prompt": "Start in operator mode: inspect repo state, run the minimal validation command, and narrate progress while editing only when the shell evidence says it is time.",
        },
        {
            "title": "Long arcs inside a few repos",
            "summary": "A small set of repos dominates the corpus, especially Codex, Dynamo, and the SGLang family.",
            "detail": (
                f"The report clusters around {join_labels(top_repos[:3])}, which makes project-aware kickoff prompts and memory references especially valuable."
            ),
            "prompt": "Ground yourself in the active project memory, recent branch state, and the last known blocker before touching code in this repo.",
        },
        {
            "title": "Meta-tooling is part of the workload",
            "summary": "You do not just use the scaffold; you actively improve it.",
            "detail": (
                f"Goal categories like {join_labels([label.lower() for label in top_items(dict(goal_counter), 3)])} show up alongside scaffold and memory sessions, so tooling upkeep is a real workstream."
            ),
            "prompt": "Treat this as scaffolding work: inspect the recent session logs, identify recurring friction, make the smallest durable improvement, and regenerate any derived artifacts.",
        },
    ]


def build_horizon_cards() -> list[dict[str, str]]:
    return [
        {
            "title": "Autonomous pre-push validation",
            "possible": "A background validation pass could run cargo/pytest/formatting checks before Codex ever suggests a push, turning many error-heavy sessions into clean one-pass loops.",
            "tip": "The report already surfaces the signal for this; the next step is a repo-aware validation wrapper or dedicated skill.",
        },
        {
            "title": "Per-project and per-branch insights slices",
            "possible": "Instead of one global report, you could generate Codex insights for just Dynamo, just Codex, or just the current branch family to see what kind of work is actually consuming time.",
            "tip": "The generator already writes machine-readable session JSON, so adding `--repo` or `--match` filters would be straightforward.",
        },
        {
            "title": "Workflow-aware session starts",
            "possible": "Codex could infer whether a session is a review, merge, benchmark, or scaffold-maintenance task and switch to the right checklist automatically before you restate the pattern.",
            "tip": "That would directly attack the biggest source of friction in this corpus: repeated context rebuilding and early-session misalignment.",
        },
    ]


def build_feedback_cards() -> list[dict[str, str]]:
    return [
        {
            "kind": "team-card",
            "title": "Built-in local insights would help",
            "detail": "This report had to be reconstructed from raw JSONL. A built-in Codex insights export would remove that reverse-engineering step and make the feature first-class.",
        },
        {
            "kind": "team-card",
            "title": "Tool-failure attribution should be structured",
            "detail": "Right now failures have to be inferred from free-form tool output. Explicit exit codes, command families, and normalized failure reasons would make the friction analysis much sharper.",
        },
        {
            "kind": "model-card",
            "title": "Session archetypes should be explicit",
            "detail": "Your corpus clearly contains repeatable session types. If Codex surfaced those natively, it could start with the right checklist instead of waiting for you to re-teach the workflow each time.",
        },
    ]


def render_prompt_block(prompt: str, ident: str) -> str:
    return (
        "<div class='pattern-prompt'>"
        "<div class='prompt-label'>Copyable Prompt</div>"
        f"<code id='{ident}'>{html.escape(prompt)}</code>"
        f"<button class='copy-btn' onclick=\"copyPrompt('{ident}', this)\">Copy</button>"
        "</div>"
    )


def render_big_wins(cards: list[dict[str, str]]) -> str:
    return "".join(
        "<div class='big-win'>"
        f"<div class='big-win-title'>{html.escape(card['title'])}</div>"
        f"<div class='big-win-desc'>{html.escape(card['desc'])}</div>"
        "</div>"
        for card in cards
    )


def render_friction_categories(cards: list[dict[str, Any]]) -> str:
    rendered = []
    for card in cards:
        examples = "".join(f"<li>{html.escape(example)}</li>" for example in card["examples"])
        rendered.append(
            "<div class='friction-category'>"
            f"<div class='friction-title'>{html.escape(card['title'])}</div>"
            f"<div class='friction-desc'>{html.escape(card['desc'])}</div>"
            f"<ul class='friction-examples'>{examples}</ul>"
            "</div>"
        )
    return "".join(rendered)


def render_feature_cards(cards: list[dict[str, str]], prefix: str) -> str:
    rendered = []
    for idx, card in enumerate(cards, start=1):
        ident = f"{prefix}-{idx}"
        rendered.append(
            "<div class='feature-card'>"
            f"<div class='feature-title'>{html.escape(card['title'])}</div>"
            f"<div class='feature-oneliner'>{html.escape(card['oneliner'])}</div>"
            f"<div class='feature-why'>{html.escape(card['why'])}</div>"
            f"{render_prompt_block(card['prompt'], ident)}"
            "</div>"
        )
    return "".join(rendered)


def render_pattern_cards(cards: list[dict[str, str]], prefix: str) -> str:
    rendered = []
    for idx, card in enumerate(cards, start=1):
        ident = f"{prefix}-{idx}"
        rendered.append(
            "<div class='pattern-card'>"
            f"<div class='pattern-title'>{html.escape(card['title'])}</div>"
            f"<div class='pattern-summary'>{html.escape(card['summary'])}</div>"
            f"<div class='pattern-detail'>{html.escape(card['detail'])}</div>"
            f"{render_prompt_block(card['prompt'], ident)}"
            "</div>"
        )
    return "".join(rendered)


def render_horizon_cards(cards: list[dict[str, str]]) -> str:
    return "".join(
        "<div class='horizon-card'>"
        f"<div class='horizon-title'>{html.escape(card['title'])}</div>"
        f"<div class='horizon-possible'>{html.escape(card['possible'])}</div>"
        f"<div class='horizon-tip'>{html.escape(card['tip'])}</div>"
        "</div>"
        for card in cards
    )


def render_feedback_cards(cards: list[dict[str, str]]) -> str:
    return "".join(
        f"<div class='feedback-card {html.escape(card['kind'])}'>"
        f"<div class='feedback-title'>{html.escape(card['title'])}</div>"
        f"<div class='feedback-detail'>{html.escape(card['detail'])}</div>"
        "</div>"
        for card in cards
    )


def render_project_areas(areas: list[dict[str, Any]]) -> str:
    return "".join(
        "<div class='project-area'>"
        "<div class='area-header'>"
        f"<span class='area-name'>{html.escape(area['label'])}</span>"
        f"<span class='area-count'>~{format_int(area['count'])} sessions</span>"
        "</div>"
        f"<div class='area-desc'>{html.escape(area['desc'])}</div>"
        "</div>"
        for area in areas[:5]
    )


def render_session_rows(enriched_sessions: list[EnrichedSession]) -> str:
    rows = []
    for enriched in enriched_sessions:
        session = enriched.session
        rows.append(
            "<details class='session-card'>"
            "<summary>"
            f"<span class='session-repo'>{html.escape(display_repo_name(session.repo))}</span>"
            f"<span class='session-meta'>{html.escape(session.start_time[:10])} • "
            f"{format_duration(session.duration_minutes)} • "
            f"{session.tool_counts.get('exec_command', 0)} shell • "
            f"{session.tool_errors} errors</span>"
            "</summary>"
            f"<div class='session-prompt'>{html.escape(session.first_prompt)}</div>"
            "<div class='session-grid'>"
            f"<div><strong>Goal Categories</strong><br>{html.escape(', '.join(f'{k} x{v}' for k, v in list(enriched.goal_categories.items())[:4]) or 'none')}</div>"
            f"<div><strong>Top commands</strong><br>{html.escape(', '.join(f'{k} x{v}' for k, v in list(session.command_prefixes.items())[:4]) or 'none')}</div>"
            f"<div><strong>Outcome</strong><br>{html.escape(enriched.outcome)} / {html.escape(enriched.primary_success)}</div>"
            f"<div><strong>Friction</strong><br>{html.escape(enriched.friction_detail or 'low visible friction')}</div>"
            "</div>"
            "</details>"
        )
    return "".join(rows)


def build_report(summaries: list[SessionSummary], output_dir: Path) -> tuple[str, dict[str, Any]]:
    sessions = sorted(summaries, key=lambda item: item.start_time)
    session_count = len(sessions)
    if not sessions:
        raise RuntimeError("No sessions matched the selected filters.")

    enriched_sessions = [enrich_session(session) for session in sessions]
    start_date = sessions[0].start_time[:10]
    end_date = sessions[-1].start_time[:10]
    active_days = {session.start_time[:10] for session in sessions}
    total_messages = sum(session.user_message_count + session.assistant_message_count for session in sessions)
    total_duration = sum(session.duration_minutes for session in sessions)
    total_input = sum(session.input_tokens for session in sessions)
    total_output = sum(session.output_tokens for session in sessions)
    total_cached = sum(session.cached_input_tokens for session in sessions)
    total_errors = sum(session.tool_errors for session in sessions)
    total_corrections = sum(session.correction_signals for session in sessions)
    total_pushes = sum(session.git_pushes for session in sessions)
    total_commits = sum(session.git_commits for session in sessions)
    total_commentary = sum(session.commentary_count for session in sessions)
    total_final = sum(session.final_count for session in sessions)

    tool_counter: Counter[str] = Counter()
    command_counter: Counter[str] = Counter()
    failure_counter: Counter[str] = Counter()
    repo_counter: Counter[str] = Counter()
    duration_by_repo: Counter[str] = Counter()
    extension_counter: Counter[str] = Counter()
    goal_counter: Counter[str] = Counter()
    friction_counter: Counter[str] = Counter()
    delegated_sessions = 0
    github_app_sessions = 0
    plan_sessions = 0

    for enriched in enriched_sessions:
        session = enriched.session
        tool_counter.update(session.tool_counts)
        command_counter.update(session.command_prefixes)
        failure_counter.update(session.failed_command_prefixes)
        repo_counter[session.repo] += 1
        duration_by_repo[session.repo] += session.duration_minutes
        extension_counter.update(session.touched_extensions)
        goal_counter.update(enriched.goal_categories)
        friction_counter.update(enriched.friction_counts)
        delegated_sessions += int(session.uses_subagents)
        github_app_sessions += int(session.uses_github_app)
        plan_sessions += int(session.uses_update_plan)

    duration_order = sorted(duration_by_repo.items(), key=lambda item: item[1], reverse=True)
    preferred_top_repo = next((repo for repo, _ in duration_order if repo not in GENERIC_REPOS), None)
    project_area_cards = project_areas(enriched_sessions)
    usage_paragraphs = usage_narrative(
        enriched_sessions,
        goal_counter,
        tool_counter,
        command_counter,
        duration_by_repo,
        total_commentary,
        total_final,
        delegated_sessions,
    )
    glance = at_a_glance(
        goal_counter,
        friction_counter,
        duration_by_repo,
        total_errors,
        delegated_sessions,
        total_pushes,
        total_commits,
    )
    big_wins = build_big_wins(enriched_sessions)
    friction_sections = build_friction_sections(enriched_sessions)
    feature_cards = build_feature_cards(
        total_errors,
        total_pushes,
        total_commits,
        total_corrections,
        delegated_sessions,
    )
    pattern_cards = build_pattern_cards(goal_counter, command_counter, repo_counter)
    horizon_cards = build_horizon_cards()
    feedback_cards = build_feedback_cards()
    stats_html = (
        f"<div class='stat'><div class='stat-value'>{format_int(total_messages)}</div><div class='stat-label'>Messages</div></div>"
        f"<div class='stat'><div class='stat-value'>{format_int(tool_counter.get('exec_command', 0))}</div><div class='stat-label'>Shell Calls</div></div>"
        f"<div class='stat'><div class='stat-value'>{format_int(sum(1 for repo in repo_counter if repo not in GENERIC_REPOS))}</div><div class='stat-label'>Repo Areas</div></div>"
        f"<div class='stat'><div class='stat-value'>{format_int(len(active_days))}</div><div class='stat-label'>Days</div></div>"
        f"<div class='stat'><div class='stat-value'>{(total_messages / max(1, len(active_days))):.1f}</div><div class='stat-label'>Msgs/Day</div></div>"
    )

    report_context = {
        "session_count": session_count,
        "start_date": start_date,
        "end_date": end_date,
        "active_days": len(active_days),
        "total_messages": total_messages,
        "total_duration_minutes": total_duration,
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "cached_input_tokens": total_cached,
        "total_errors": total_errors,
        "total_corrections": total_corrections,
        "total_pushes": total_pushes,
        "total_commits": total_commits,
        "total_commentary": total_commentary,
        "total_final": total_final,
        "delegated_sessions": delegated_sessions,
        "github_app_sessions": github_app_sessions,
        "plan_sessions": plan_sessions,
        "top_repo": display_repo_name(preferred_top_repo or (repo_counter.most_common(1)[0][0] if repo_counter else "n/a")),
        "top_command": command_counter.most_common(1)[0][0] if command_counter else "n/a",
        "goal_categories": dict(goal_counter.most_common()),
        "friction_categories": dict(friction_counter.most_common()),
        "at_a_glance": glance,
        "output_dir": str(output_dir),
    }

    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Codex Insights</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ font-family: Inter, "Segoe UI", sans-serif; background: #f8fafc; color: #334155; line-height: 1.65; padding: 48px 24px; }}
    .container {{ max-width: 860px; margin: 0 auto; }}
    h1 {{ font-size: 32px; font-weight: 700; color: #0f172a; margin-bottom: 8px; }}
    h2 {{ font-size: 20px; font-weight: 600; color: #0f172a; margin-top: 48px; margin-bottom: 16px; }}
    .subtitle {{ color: #64748b; font-size: 15px; margin-bottom: 20px; }}
    .nav-toc {{ display: flex; flex-wrap: wrap; gap: 8px; margin: 24px 0 32px 0; padding: 16px; background: white; border-radius: 8px; border: 1px solid #e2e8f0; }}
    .nav-toc a {{ font-size: 12px; color: #64748b; text-decoration: none; padding: 6px 12px; border-radius: 6px; background: #f1f5f9; transition: all 0.15s; }}
    .nav-toc a:hover {{ background: #e2e8f0; color: #334155; }}
    .stats-row {{ display: flex; gap: 24px; margin-bottom: 40px; padding: 20px 0; border-top: 1px solid #e2e8f0; border-bottom: 1px solid #e2e8f0; flex-wrap: wrap; }}
    .stat {{ text-align: center; }}
    .stat-value {{ font-size: 24px; font-weight: 700; color: #0f172a; }}
    .stat-label {{ font-size: 11px; color: #64748b; text-transform: uppercase; }}
    .at-a-glance {{ background: linear-gradient(135deg, #fef3c7 0%, #fde68a 100%); border: 1px solid #f59e0b; border-radius: 12px; padding: 20px 24px; margin-bottom: 32px; }}
    .glance-title {{ font-size: 16px; font-weight: 700; color: #92400e; margin-bottom: 16px; }}
    .glance-sections {{ display: flex; flex-direction: column; gap: 12px; }}
    .glance-section {{ font-size: 14px; color: #78350f; line-height: 1.6; }}
    .glance-section strong {{ color: #92400e; }}
    .see-more {{ color: #b45309; text-decoration: none; font-size: 13px; white-space: nowrap; }}
    .see-more:hover {{ text-decoration: underline; }}
    .project-areas {{ display: flex; flex-direction: column; gap: 12px; margin-bottom: 32px; }}
    .project-area {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }}
    .area-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }}
    .area-name {{ font-weight: 600; font-size: 15px; color: #0f172a; }}
    .area-count {{ font-size: 12px; color: #64748b; background: #f1f5f9; padding: 2px 8px; border-radius: 4px; }}
    .area-desc {{ font-size: 14px; color: #475569; line-height: 1.5; }}
    .narrative {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px; margin-bottom: 24px; }}
    .narrative p {{ margin-bottom: 12px; font-size: 14px; color: #475569; line-height: 1.7; }}
    .narrative p:last-child {{ margin-bottom: 0; }}
    .section-intro {{ font-size: 14px; color: #64748b; margin-bottom: 16px; }}
    .big-wins {{ display: flex; flex-direction: column; gap: 12px; margin-bottom: 24px; }}
    .big-win {{ background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; padding: 16px; }}
    .big-win-title {{ font-weight: 600; font-size: 15px; color: #166534; margin-bottom: 8px; }}
    .big-win-desc {{ font-size: 14px; color: #15803d; line-height: 1.5; }}
    .friction-categories {{ display: flex; flex-direction: column; gap: 16px; margin-bottom: 24px; }}
    .friction-category {{ background: #fef2f2; border: 1px solid #fca5a5; border-radius: 8px; padding: 16px; }}
    .friction-title {{ font-weight: 600; font-size: 15px; color: #991b1b; margin-bottom: 6px; }}
    .friction-desc {{ font-size: 13px; color: #7f1d1d; margin-bottom: 10px; }}
    .friction-examples {{ margin: 0 0 0 20px; font-size: 13px; color: #334155; }}
    .friction-examples li {{ margin-bottom: 4px; }}
    .features-section, .patterns-section {{ display: flex; flex-direction: column; gap: 12px; margin: 16px 0; }}
    .feature-card {{ background: #f0fdf4; border: 1px solid #86efac; border-radius: 8px; padding: 16px; }}
    .pattern-card {{ background: #f0f9ff; border: 1px solid #7dd3fc; border-radius: 8px; padding: 16px; }}
    .feature-title, .pattern-title {{ font-weight: 600; font-size: 15px; color: #0f172a; margin-bottom: 6px; }}
    .feature-oneliner {{ font-size: 14px; color: #475569; margin-bottom: 8px; }}
    .pattern-summary {{ font-size: 14px; color: #475569; margin-bottom: 8px; }}
    .feature-why, .pattern-detail {{ font-size: 13px; color: #334155; line-height: 1.5; }}
    .pattern-prompt {{ background: #f8fafc; padding: 12px; border-radius: 6px; margin-top: 12px; border: 1px solid #e2e8f0; position: relative; }}
    .pattern-prompt code {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; color: #334155; display: block; white-space: pre-wrap; margin-bottom: 8px; padding-right: 56px; }}
    .prompt-label {{ font-size: 11px; font-weight: 600; text-transform: uppercase; color: #64748b; margin-bottom: 6px; }}
    .copy-btn {{ background: #e2e8f0; border: none; border-radius: 4px; padding: 4px 8px; font-size: 11px; cursor: pointer; color: #475569; position: absolute; top: 10px; right: 10px; }}
    .copy-btn:hover {{ background: #cbd5e1; }}
    .copy-btn.copied {{ background: #16a34a; color: white; }}
    .charts-row {{ display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin: 24px 0; }}
    .chart-card {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }}
    .chart-title {{ font-size: 12px; font-weight: 600; color: #64748b; text-transform: uppercase; margin-bottom: 12px; }}
    .bar-row {{ display: flex; align-items: center; margin-bottom: 6px; }}
    .bar-label {{ width: 140px; font-size: 11px; color: #475569; flex-shrink: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
    .bar-track {{ flex: 1; height: 6px; background: #f1f5f9; border-radius: 3px; margin: 0 8px; }}
    .bar-fill {{ height: 100%; border-radius: 3px; }}
    .bar-value {{ width: 42px; font-size: 11px; font-weight: 500; color: #64748b; text-align: right; }}
    .empty {{ color: #94a3b8; font-size: 13px; }}
    .horizon-section {{ display: flex; flex-direction: column; gap: 16px; }}
    .horizon-card {{ background: linear-gradient(135deg, #faf5ff 0%, #f5f3ff 100%); border: 1px solid #c4b5fd; border-radius: 8px; padding: 16px; }}
    .horizon-title {{ font-weight: 600; font-size: 15px; color: #5b21b6; margin-bottom: 8px; }}
    .horizon-possible {{ font-size: 14px; color: #334155; margin-bottom: 10px; line-height: 1.5; }}
    .horizon-tip {{ font-size: 13px; color: #6b21a8; background: rgba(255,255,255,0.6); padding: 8px 12px; border-radius: 4px; }}
    .feedback-header {{ margin-top: 48px; color: #64748b; font-size: 16px; }}
    .feedback-intro {{ font-size: 13px; color: #94a3b8; margin-bottom: 16px; }}
    .feedback-card {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; margin-bottom: 12px; }}
    .feedback-card.team-card {{ background: #eff6ff; border-color: #bfdbfe; }}
    .feedback-card.model-card {{ background: #faf5ff; border-color: #e9d5ff; }}
    .feedback-title {{ font-weight: 600; font-size: 14px; color: #0f172a; margin-bottom: 6px; }}
    .feedback-detail {{ font-size: 13px; color: #475569; line-height: 1.5; }}
    .session-card {{ border: 1px solid #e2e8f0; border-radius: 8px; background: white; margin-bottom: 10px; }}
    .session-card summary {{ cursor: pointer; list-style: none; display: flex; justify-content: space-between; gap: 12px; padding: 14px 16px; font-weight: 600; }}
    .session-card summary::-webkit-details-marker {{ display: none; }}
    .session-repo {{ color: #0f172a; }}
    .session-meta {{ color: #64748b; font-weight: 400; font-size: 13px; }}
    .session-prompt {{ padding: 0 16px 8px; color: #475569; font-size: 13px; }}
    .session-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px; padding: 0 16px 16px; font-size: 12px; color: #475569; }}
    .footer {{ color: #64748b; font-size: 13px; line-height: 1.7; }}
    @media (max-width: 640px) {{ .charts-row {{ grid-template-columns: 1fr; }} .stats-row {{ justify-content: center; }} .session-card summary {{ flex-direction: column; }} .session-grid {{ grid-template-columns: 1fr; }} }}
  </style>
</head>
<body>
  <div class="container">
    <h1>Codex Insights</h1>
    <p class="subtitle">{format_int(total_messages)} messages across {format_int(session_count)} sessions | {start_date} to {end_date}</p>

    <div class="at-a-glance">
      <div class="glance-title">At a Glance</div>
      <div class="glance-sections">
        <div class="glance-section"><strong>What's working:</strong> {html.escape(glance['working'])} <a href="#section-wins" class="see-more">Impressive Things You Did →</a></div>
        <div class="glance-section"><strong>What's hindering you:</strong> {html.escape(glance['hindering'])} <a href="#section-friction" class="see-more">Where Things Go Wrong →</a></div>
        <div class="glance-section"><strong>Quick wins to try:</strong> {html.escape(glance['quick_wins'])} <a href="#section-features" class="see-more">Features to Try →</a></div>
        <div class="glance-section"><strong>Ambitious workflows:</strong> {html.escape(glance['ambitious'])} <a href="#section-horizon" class="see-more">On the Horizon →</a></div>
      </div>
    </div>

    <nav class="nav-toc">
      <a href="#section-work">What You Work On</a>
      <a href="#section-usage">How You Use Codex</a>
      <a href="#section-wins">Impressive Things</a>
      <a href="#section-friction">Where Things Go Wrong</a>
      <a href="#section-features">Features to Try</a>
      <a href="#section-patterns">New Usage Patterns</a>
      <a href="#section-horizon">On the Horizon</a>
      <a href="#section-feedback">Team Feedback</a>
    </nav>

    <div class="stats-row">{stats_html}</div>

    <h2 id="section-work">What You Work On</h2>
    <div class="project-areas">{render_project_areas(project_area_cards)}</div>

    <h2 id="section-usage">How You Use Codex</h2>
    <div class="narrative">
      <p>{html.escape(usage_paragraphs[0])}</p>
      <p>{html.escape(usage_paragraphs[1])}</p>
    </div>

    <div class="charts-row">
      <div class="chart-card">
        <div class="chart-title">What You Wanted</div>
        {bar_rows(goal_counter, "#2563eb")}
      </div>
      <div class="chart-card">
        <div class="chart-title">Top Tools Used</div>
        {bar_rows(tool_counter, "#0891b2")}
      </div>
    </div>

    <div class="charts-row">
      <div class="chart-card">
        <div class="chart-title">Top Commands</div>
        {bar_rows(command_counter, "#0f766e")}
      </div>
      <div class="chart-card">
        <div class="chart-title">Friction Markers</div>
        {bar_rows(failure_counter, "#dc2626")}
      </div>
    </div>

    <h2 id="section-wins">Impressive Things You Did</h2>
    <p class="section-intro">A few standout sessions where the logs show sustained throughput, persistence, or a high amount of real delivery work.</p>
    <div class="big-wins">{render_big_wins(big_wins)}</div>

    <h2 id="section-friction">Where Things Go Wrong</h2>
    <p class="section-intro">These categories are heuristic, but they line up with the dominant failure patterns in the local session logs.</p>
    <div class="friction-categories">{render_friction_categories(friction_sections)}</div>

    <h2 id="section-features">Features to Try</h2>
    <p class="section-intro">Concrete workflow changes that fit the actual shape of your Codex sessions.</p>
    <div class="features-section">{render_feature_cards(feature_cards, 'feature')}</div>

    <h2 id="section-patterns">New Usage Patterns</h2>
    <p class="section-intro">Stable patterns showing up across the corpus, with prompts you can reuse directly.</p>
    <div class="patterns-section">{render_pattern_cards(pattern_cards, 'pattern')}</div>

    <h2 id="section-horizon">On the Horizon</h2>
    <div class="horizon-section">{render_horizon_cards(horizon_cards)}</div>

    <h2 id="section-feedback">Team Feedback</h2>
    <p class="feedback-intro">Notes this corpus suggests for the Codex product and for future scaffold improvements.</p>
    <div class="feedback-section">{render_feedback_cards(feedback_cards)}</div>

    <h2>Recent Sessions</h2>
    <p class="section-intro">Most recent sessions first. Open one to see the derived goal, outcome, and friction summary.</p>
    {render_session_rows(list(reversed(enriched_sessions[-12:])))}

    <h2>Artifacts</h2>
    <p class="section-intro">This run also wrote per-session machine-readable outputs alongside the HTML report.</p>
    <div class="narrative">
      <div class="footer">
        {html.escape(str(output_dir / 'report.html'))}<br>
        {html.escape(str(output_dir / 'session-meta'))}<br>
        {html.escape(str(output_dir / 'facets'))}<br>
        {html.escape(str(output_dir / 'manifest.json'))}
      </div>
    </div>
  </div>
  <script>
    function copyPrompt(id, button) {{
      const text = document.getElementById(id).innerText;
      navigator.clipboard.writeText(text).then(() => {{
        const old = button.innerText;
        button.innerText = 'Copied';
        button.classList.add('copied');
        setTimeout(() => {{
          button.innerText = old;
          button.classList.remove('copied');
        }}, 1200);
      }});
    }}
  </script>
</body>
</html>
"""
    return html_body, report_context


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    if args.codex_home:
        resolved_codex_home = Path(args.codex_home).expanduser()
    else:
        resolved_codex_home = codex_home()
    sessions_root = (
        Path(args.sessions_root).expanduser()
        if args.sessions_root
        else resolved_codex_home / "sessions"
    )
    output_dir = (
        Path(args.output_dir).expanduser()
        if args.output_dir
        else resolved_codex_home / "usage-data"
    )
    session_meta_dir = output_dir / "session-meta"
    facets_dir = output_dir / "facets"
    session_meta_dir.mkdir(parents=True, exist_ok=True)
    facets_dir.mkdir(parents=True, exist_ok=True)
    for stale in session_meta_dir.glob("*.json"):
        stale.unlink()
    for stale in facets_dir.glob("*.json"):
        stale.unlink()

    if not sessions_root.exists():
        raise SystemExit(f"Sessions root does not exist: {sessions_root}")

    files = sorted(sessions_root.rglob("*.jsonl"), key=lambda path: path.stat().st_mtime)
    if args.days is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
        files = [
            path
            for path in files
            if datetime.fromtimestamp(path.stat().st_mtime, timezone.utc) >= cutoff
        ]
    if args.limit is not None:
        files = files[-args.limit :]

    summaries: list[SessionSummary] = []
    for path in files:
        summary = analyze_session(path)
        if summary is None:
            continue
        summaries.append(summary)
        write_json(session_meta_dir / f"{summary.output_key}.json", asdict(summary))
        write_json(facets_dir / f"{summary.output_key}.json", build_facets(summary))

    report_html, manifest = build_report(summaries, output_dir)
    (output_dir / "report.html").write_text(report_html, encoding="utf-8")
    write_json(output_dir / "manifest.json", manifest)

    print(f"Analyzed {len(summaries)} sessions")
    print(f"Report: {output_dir / 'report.html'}")
    print(f"Session metadata: {session_meta_dir}")
    print(f"Facets: {facets_dir}")


if __name__ == "__main__":
    main()
