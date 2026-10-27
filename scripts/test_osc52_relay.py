#!/usr/bin/env python3
"""
Unit and regression tests for scripts/osc52-relay.py security hardening.
"""

import base64
import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

# Load scripts/osc52-relay.py as a module
SCRIPT_PATH = os.path.join(os.path.dirname(__file__), "osc52-relay.py")
spec = importlib.util.spec_from_file_location("osc52_relay", SCRIPT_PATH)
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)


class TestOsc52RelaySecurity(unittest.TestCase):
    def test_filter_osc52_set(self):
        buf = b"hello\x1b]52;c;dGVzdA==\x07world"
        out, rem, events = relay.filter_osc52(buf)
        self.assertEqual(out, b"helloworld")
        self.assertEqual(rem, b"")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0], (b"c", b"dGVzdA=="))

    def test_filter_osc52_set_st_terminated(self):
        buf = b"abc\x1b]52;c;dGVzdA==\x1b\\def"
        out, rem, events = relay.filter_osc52(buf)
        self.assertEqual(out, b"abcdef")
        self.assertEqual(rem, b"")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0], (b"c", b"dGVzdA=="))

    def test_filter_osc52_query(self):
        buf = b"foo\x1b]52;c;?\x07bar"
        out, rem, events = relay.filter_osc52(buf)
        self.assertEqual(out, b"foobar")
        self.assertEqual(rem, b"")
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0], (b"c", None))

    def test_clip_cmds_rejects_paste_by_default(self):
        with patch.dict(os.environ, {"OMAGUAKE_CLIP_PASTE": "wl-paste -n"}):
            copy, paste = relay.clip_cmds(allow_read=False)
            self.assertIsNotNone(copy)
            self.assertIsNone(paste, "paste_cmd must be None when allow_read is False")

    def test_clip_cmds_permits_paste_when_explicitly_allowed(self):
        with patch.dict(os.environ, {"OMAGUAKE_CLIP_PASTE": "my-paste -k"}):
            copy, paste = relay.clip_cmds(allow_read=True)
            self.assertEqual(paste, ["my-paste", "-k"])

    def test_handle_event_query_rejected_by_default(self):
        # Even if a paste_cmd was somehow passed, if allow_read=False it MUST be rejected
        master_mock = 999
        paste_cmd = ["wl-paste", "-n"]
        copy_cmd = ["wl-copy"]

        with patch("subprocess.run") as mock_run, patch("os.write") as mock_write:
            res = relay.handle_event(
                b"c",
                None,  # query event
                master_mock,
                copy_cmd,
                paste_cmd=paste_cmd,
                allow_read=False,
            )
            self.assertIsNone(res)
            mock_run.assert_not_called()
            mock_write.assert_not_called()

    def test_handle_event_copy_succeeds(self):
        master_mock = 999
        copy_cmd = ["wl-copy"]
        payload = base64.b64encode(b"secret password to copy")

        with patch("subprocess.run") as mock_run:
            res = relay.handle_event(
                b"c",
                payload,
                master_mock,
                copy_cmd,
                paste_cmd=None,
                allow_read=False,
            )
            self.assertIsNone(res)
            mock_run.assert_called_once_with(
                copy_cmd, input=b"secret password to copy", check=False, timeout=relay.COPY_TIMEOUT
            )

    def test_handle_event_copy_invalid_base64_ignored(self):
        master_mock = 999
        copy_cmd = ["wl-copy"]

        with patch("subprocess.run") as mock_run:
            res = relay.handle_event(
                b"c",
                b"not-valid-base64!!?",
                master_mock,
                copy_cmd,
                paste_cmd=None,
                allow_read=False,
            )
            self.assertIsNone(res)
            mock_run.assert_not_called()

    def test_handle_event_query_allowed_output_limit(self):
        master_mock = 999
        paste_cmd = ["wl-paste", "-n"]
        copy_cmd = ["wl-copy"]
        read_state = {"time": 0.0}

        huge_data = b"X" * (relay.MAX_READ_BYTES + 1000)
        proc_result = MagicMock()
        proc_result.stdout = huge_data

        with patch("subprocess.run", return_value=proc_result) as mock_run, \
             patch("os.write") as mock_write, \
             patch("termios.tcgetattr", return_value=[0, 0, 0, 0, 0, 0, 0]), \
             patch("termios.tcsetattr"):
            res = relay.handle_event(
                b"c",
                None,
                master_mock,
                copy_cmd,
                paste_cmd=paste_cmd,
                allow_read=True,
                last_read_state=read_state,
            )
            self.assertIsNotNone(res)
            # Response should contain base64 of capped data
            capped_b64 = base64.b64encode(b"X" * relay.MAX_READ_BYTES)
            expected_resp = b"\x1b]52;c;" + capped_b64 + b"\x07"
            self.assertEqual(res, expected_resp)
            mock_write.assert_called_once_with(master_mock, expected_resp)

    def test_handle_event_query_rate_limiting(self):
        master_mock = 999
        paste_cmd = ["wl-paste", "-n"]
        copy_cmd = ["wl-copy"]
        read_state = {"time": time.monotonic()}  # Just read now

        with patch("subprocess.run") as mock_run, patch("os.write") as mock_write:
            res = relay.handle_event(
                b"c",
                None,
                master_mock,
                copy_cmd,
                paste_cmd=paste_cmd,
                allow_read=True,
                last_read_state=read_state,
            )
            self.assertIsNone(res, "Subsequent query within MIN_READ_INTERVAL must be dropped")
            mock_run.assert_not_called()
            mock_write.assert_not_called()

    def test_handle_event_query_idle_timeout(self):
        master_mock = 999
        paste_cmd = ["wl-paste", "-n"]
        copy_cmd = ["wl-copy"]
        read_state = {"time": 0.0}
        last_key = time.monotonic() - (relay.MAX_IDLE_SECONDS + 5.0)

        with patch("subprocess.run") as mock_run, patch("os.write") as mock_write:
            res = relay.handle_event(
                b"c",
                None,
                master_mock,
                copy_cmd,
                paste_cmd=paste_cmd,
                allow_read=True,
                last_read_state=read_state,
                last_key=last_key,
            )
            self.assertIsNone(res, "Query when user has been idle must be dropped")
            mock_run.assert_not_called()
            mock_write.assert_not_called()

    def test_handle_event_echo_restored_on_write_error(self):
        master_mock = 999
        paste_cmd = ["wl-paste", "-n"]
        copy_cmd = ["wl-copy"]
        read_state = {"time": 0.0}
        proc_result = MagicMock()
        proc_result.stdout = b"clip_data"

        orig_attrs = [0, 0, 0, relay.termios.ECHO, 0, 0, 0]
        set_attrs_calls = []

        def fake_tcsetattr(fd, when, attrs):
            set_attrs_calls.append(attrs[3])

        with patch("subprocess.run", return_value=proc_result), \
             patch("os.write", side_effect=OSError("write failed")), \
             patch("termios.tcgetattr", return_value=list(orig_attrs)), \
             patch("termios.tcsetattr", side_effect=fake_tcsetattr):
            res = relay.handle_event(
                b"c",
                None,
                master_mock,
                copy_cmd,
                paste_cmd=paste_cmd,
                allow_read=True,
                last_read_state=read_state,
            )
            self.assertIsNone(res)
            # Check that ECHO was disabled, then restored in finally block
            self.assertGreaterEqual(len(set_attrs_calls), 2)
            self.assertEqual(set_attrs_calls[0] & relay.termios.ECHO, 0)
            self.assertNotEqual(set_attrs_calls[-1] & relay.termios.ECHO, 0)


if __name__ == "__main__":
    unittest.main()
