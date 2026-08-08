"""Small regression checks for ACP routing and permission boundaries."""

import importlib.util
import sys
import unittest
from argparse import Namespace
from pathlib import Path
from types import SimpleNamespace

_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "phone_a_friend.py"
_spec = importlib.util.spec_from_file_location("phone_a_friend", _SCRIPT)
phone_a_friend = importlib.util.module_from_spec(_spec)
sys.modules["phone_a_friend"] = phone_a_friend
_spec.loader.exec_module(phone_a_friend)


class TestPhoneAFriend(unittest.IsolatedAsyncioTestCase):
    def test_fast_auto_routes_to_devin_acp(self):
        resolved = phone_a_friend.resolve(
            Namespace(friend="auto", speed="fast", capability="verify", model=None)
        )

        self.assertEqual(resolved.friend, "devin")
        self.assertEqual(resolved.command, ("devin", "acp"))
        self.assertEqual(resolved.model, "swe-1-7-lightning")

    def test_parallel_act_requires_separate_confirmation(self):
        args = Namespace(
            cwd=Path("/tmp"),
            add_dir=[],
            chat=False,
            prompt=["one", "two"],
            dry_run=False,
            capability="act",
            confirm_parallel_act=False,
            timeout_seconds=30,
            speed="fast",
        )

        self.assertIn("--confirm-parallel-act", phone_a_friend.validate_args(args))

    async def test_verify_rejects_and_act_allows_once(self):
        options = [
            SimpleNamespace(kind="reject_once", option_id="no"),
            SimpleNamespace(kind="allow_once", option_id="yes"),
        ]

        denied = await phone_a_friend.FriendClient("verify").request_permission(
            "session", object(), options
        )
        allowed = await phone_a_friend.FriendClient("act").request_permission(
            "session", object(), options
        )

        self.assertEqual(denied["outcome"]["outcome"], "cancelled")
        self.assertEqual(allowed["outcome"]["optionId"], "yes")

    async def test_only_agent_message_text_becomes_response(self):
        client = phone_a_friend.FriendClient("verify")
        client.start_turn("session")
        await client.session_update(
            "session",
            SimpleNamespace(
                session_update="agent_thought_chunk",
                content=SimpleNamespace(type="text", text="hidden"),
            ),
        )
        await client.session_update(
            "session",
            SimpleNamespace(
                session_update="agent_message_chunk",
                content=SimpleNamespace(type="text", text="answer"),
            ),
        )

        self.assertEqual(client.response("session"), "answer")


if __name__ == "__main__":
    unittest.main()
