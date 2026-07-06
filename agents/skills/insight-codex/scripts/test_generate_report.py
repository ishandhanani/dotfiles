#!/usr/bin/env python3
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("generate_report.py")
SPEC = importlib.util.spec_from_file_location("generate_report", SCRIPT)
REPORT = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = REPORT
SPEC.loader.exec_module(REPORT)


class ExtractorTest(unittest.TestCase):
    def test_semantic_failures_active_time_and_injected_context(self):
        rows = [
            ("2026-01-01T00:00:00Z", "session_meta", {"id": "s", "cwd": "/tmp/repo"}),
            ("2026-01-01T00:00:01Z", "response_item", {"type": "function_call", "name": "exec_command", "arguments": json.dumps({"cmd": "rg needle file"}), "call_id": "rg"}),
            ("2026-01-01T00:00:02Z", "response_item", {"type": "function_call_output", "call_id": "rg", "output": "Process exited with code 1\nOutput:\n"}),
            ("2026-01-01T00:00:03Z", "response_item", {"type": "function_call", "name": "exec_command", "arguments": json.dumps({"cmd": "cargo test"}), "call_id": "cargo"}),
            ("2026-01-01T00:00:04Z", "response_item", {"type": "function_call_output", "call_id": "cargo", "output": "Process running with session ID 42\n"}),
            ("2026-01-01T02:00:00Z", "response_item", {"type": "function_call", "name": "write_stdin", "arguments": json.dumps({"session_id": 42}), "call_id": "poll"}),
            ("2026-01-01T02:00:01Z", "response_item", {"type": "function_call_output", "call_id": "poll", "output": "Process exited with code 101\nOutput:\ntest failed\n"}),
            ("2026-01-01T02:00:02Z", "response_item", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<codex_internal_context source=\"goal\">ignored</codex_internal_context>"}]}),
            ("2026-01-01T02:00:03Z", "response_item", {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "review this"}]}),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "session.jsonl"
            path.write_text("".join(json.dumps({"timestamp": ts, "type": kind, "payload": payload}) + "\n" for ts, kind, payload in rows))
            summary = REPORT.analyze_session(path)

        self.assertEqual(summary.tool_errors, 1)
        self.assertEqual(summary.failed_command_prefixes, {"cargo": 1})
        self.assertEqual(summary.user_message_count, 1)
        self.assertLessEqual(summary.duration_minutes, 6)


if __name__ == "__main__":
    unittest.main()
