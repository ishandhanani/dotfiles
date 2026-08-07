"""Regression check: a successful plain-text friend answer is exposed under `response`."""

import importlib.util
import subprocess
import sys
import unittest
from argparse import Namespace
from pathlib import Path
from unittest import mock

# Load phone_a_friend from the sibling scripts directory without adding it to sys.path.
_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "phone_a_friend.py"
_spec = importlib.util.spec_from_file_location("phone_a_friend", _SCRIPT)
phone_a_friend = importlib.util.module_from_spec(_spec)
sys.modules["phone_a_friend"] = phone_a_friend
_spec.loader.exec_module(phone_a_friend)


class TestPlaintextResponse(unittest.TestCase):
    def setUp(self):
        self.resolved = phone_a_friend.Resolved(
            friend="devin",
            speed="fast",
            capability="verify",
            model=None,
        )
        self.args = Namespace(cwd=Path("/tmp"), add_dir=[], timeout_seconds=30)

    def test_devin_plain_text_is_response(self):
        with mock.patch.object(
            phone_a_friend.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                args=["devin", "-p", "test prompt"],
                returncode=0,
                stdout="Plain answer\n",
                stderr="",
            ),
        ):
            result = phone_a_friend.ask(1, "test prompt", self.resolved, self.args)

        self.assertTrue(result["ok"])
        self.assertEqual(result["response"], "Plain answer")
        self.assertNotIn("stdout", result)

    def test_empty_success_is_failure(self):
        with mock.patch.object(
            phone_a_friend.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                args=["devin", "-p", "test prompt"],
                returncode=0,
                stdout="",
                stderr="",
            ),
        ):
            result = phone_a_friend.ask(1, "test prompt", self.resolved, self.args)

        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "friend returned no response")


if __name__ == "__main__":
    unittest.main()
