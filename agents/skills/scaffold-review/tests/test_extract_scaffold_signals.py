"""Behavioral fixtures for log coverage, without executing captured commands."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "extract_scaffold_signals.py"
SPEC = importlib.util.spec_from_file_location("signals", SCRIPT)
signals = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signals)
SKILL = "/home/test/.codex/skills/example/SKILL.md"


def item(kind, **fields):
    return {"type": "response_item", "payload": {"type": kind, **fields}}


class ExtractionTests(unittest.TestCase):
    def analyze(self, *records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "session.jsonl"
            path.write_text("\n".join(json.dumps(record) for record in records))
            return signals.aggregate([path], max_corrections=20)

    def direct(self, command, call_id="read"):
        return item("function_call", name="exec_command", call_id=call_id,
                    arguments=json.dumps({"cmd": command}))

    def wrapped(self, source):
        return item("custom_tool_call", name="exec", input=source)

    def test_direct_and_wrapped_read_observations(self):
        direct = self.analyze(self.direct(f"cat {SKILL}"))
        wrapped = self.analyze(self.wrapped(
            f"text(await tools.exec_command({{cmd: {json.dumps('cat ' + SKILL)}}}));"))
        self.assertEqual(direct["top_commands"], wrapped["top_commands"])
        self.assertEqual(direct["top_files"], wrapped["top_files"])
        self.assertEqual(wrapped["skill_read_attempts"][0]["sessions"], 1)
        self.assertEqual(wrapped["skill_read_evidence"][0]["origin"], "wrapped_candidate")
        self.assertEqual(wrapped["skill_read_evidence"][0]["outcome"], "unverified")
        self.assertEqual(wrapped["skill_mentions"], [])

    def test_dynamic_arguments_are_unknown(self):
        for source in (
            "await tools.exec_command({cmd: command});",
            "await tools.exec_command({cmd: `cat ${path}`});",
            "await tools.exec_command(options);",
            'await tools.exec_command({cmd: "cat " + path});',
            'await tools.exec_command({cmd: "cat /tmp/file", ...options});',
            'await tools.exec_command({cmd: "cat /tmp/file", cmd: replacement});',
        ):
            with self.subTest(source=source):
                result = self.analyze(self.wrapped(source))
                self.assertEqual(result["coverage"]["unknown_shell_arguments"], 1)
                self.assertEqual(result["top_commands"], [])

    def test_quoted_examples_and_comments_are_not_calls(self):
        example = f'await tools.exec_command({{cmd: "cat {SKILL}"}})'
        source = f"// {example}\n/* {example} */\ntext({json.dumps(example)});"
        result = self.analyze(self.wrapped(source))
        self.assertEqual(result["skill_read_attempts"], [])
        self.assertEqual(result["coverage"]["wrappers_without_recognized_shell_calls"], 1)

    def test_multiple_calls_and_plain_template(self):
        source = f"await Promise.all([tools.exec_command({{cmd: `cat {SKILL}`}}), tools.exec_command({{cmd: 'git status', workdir: '/tmp'}})]);"
        result = self.analyze(self.wrapped(source))
        self.assertEqual(result["coverage"]["literal_wrapped_shell_candidates"], 2)
        self.assertEqual({row['name'] for row in result['top_commands']}, {'cat', 'git'})

    def test_namespaced_json_encoded_wrapper(self):
        source = f"await tools.exec_command({{cmd: {json.dumps('cat ' + SKILL)}}});"
        result = self.analyze(item("function_call", name="functions.exec", arguments=json.dumps(source)))
        self.assertEqual(result["skill_read_attempts"][0]["name"], "example")

    def test_failed_read_is_not_observed_content(self):
        result = self.analyze(self.direct(f"cat {SKILL}"), item(
            "function_call_output", call_id="read", output=json.dumps({"exit_code": 1, "output": "not found"})))
        self.assertEqual(result["skill_read_evidence"][0]["outcome"], "call_failed")
        self.assertEqual(result["skill_read_attempts"][0]["content_observed"], 0)

    def test_success_requires_matching_output_content(self):
        for output, expected in [("", "unverified"), ("---\nname: example\n---", "content_observed")]:
            with self.subTest(output=output):
                result = self.analyze(self.direct(f"cat {SKILL}"), item(
                    "function_call_output", call_id="read", output=json.dumps({"exit_code": 0, "output": output})))
                self.assertEqual(result["skill_read_evidence"][0]["outcome"], expected)

    def test_user_mentions_and_tool_reads_stay_separate(self):
        result = self.analyze(item("message", role="user", content=[{"type": "input_text", "text": "Use $example"}]),
                              self.direct(f"cat {SKILL}"))
        self.assertEqual(result["skill_mentions"], [{"name": "example", "count": 1}])
        self.assertEqual(result["skill_read_attempts"][0]["count"], 1)

    def test_echo_and_patch_paths_are_not_reads(self):
        self.assertEqual(signals.skill_reads(f"echo cat {SKILL}"), set())
        result = self.analyze(item("function_call", name="apply_patch", arguments=f"*** Update File: {SKILL}"))
        self.assertEqual(result["skill_read_attempts"], [])

    def test_multiline_and_compound_read_commands(self):
        command = f"cd /tmp\ncat {SKILL}\necho done"
        self.assertEqual(signals.skill_reads(command), {"example"})
        self.assertEqual(signals.skill_reads(f"git status && sed -n '1,20p' {SKILL}"), {"example"})

    def test_injected_context_is_not_a_correction(self):
        result = self.analyze(item("message", role="user", content=[{
            "type": "input_text", "text": "<recommended_plugins>always use $example</recommended_plugins>"}]))
        self.assertEqual(result["filtered_user_messages"], 1)
        self.assertEqual(result["skill_mentions"], [])
        self.assertEqual(result["correction_candidates"], [])

    def test_pattern_evidence_contains_match_not_unrelated_preamble(self):
        result = self.analyze(item("message", role="user", content=[{"type": "input_text", "text": "Inspect this change."}]),
                              self.direct("git status --short"))
        pattern = next(row for row in result["workflow_patterns"] if row["name"] == "git_publish")
        self.assertIn("git status", pattern["examples"][0])
        self.assertIn("Coverage", signals.markdown(result))

    def test_legacy_tool_record(self):
        result = self.analyze({"type": "assistant", "message": {"content": [{
            "type": "tool_use", "name": "Bash", "input": {"command": f"cat {SKILL}"}}]}})
        self.assertEqual(result["coverage"]["direct_shell_calls"], 1)
        self.assertEqual(result["skill_read_attempts"][0]["name"], "example")


if __name__ == "__main__":
    unittest.main()
