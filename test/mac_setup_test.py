"""Exercise the Finder installer without touching login services or opening a browser."""
from contextlib import ExitStack, redirect_stdout
from io import StringIO
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from uuid import UUID

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/install-mac.py"


class MacSetupTest(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        home = Path(stack.enter_context(tempfile.TemporaryDirectory()))
        (home / "Library").mkdir()
        node = home / "bin/node"
        node.parent.mkdir()
        node.touch()
        self.plist = home / "Library/LaunchAgents/com.otoha.stereo-bridge.plist"
        self.lan = "192.168.10.2"

        def run(args, **kwargs):
            output = {"route": "interface: en0", "ipconfig": self.lan}.get(Path(args[0]).name, "")
            return subprocess.CompletedProcess(args, 0, stdout=output)

        self.run = stack.enter_context(patch.object(subprocess, "run", side_effect=run))
        stack.enter_context(patch.object(subprocess, "check_output", side_effect=lambda cmd, **kw:
            "family-mac" if cmd[0].endswith("scutil") else "22"))
        stack.enter_context(patch("shutil.which", return_value=str(node)))
        stack.enter_context(patch.object(Path, "home", return_value=home))
        stack.enter_context(patch.object(sys, "platform", "darwin"))
        stack.enter_context(patch.object(sys, "argv", [str(SCRIPT), "--lan", "--open"]))
        response = Mock(status=200)
        response.read.return_value = b'{"short_name":"Otoha"}'
        self.connection = stack.enter_context(patch("http.client.HTTPConnection"))
        self.connection.return_value.getresponse.return_value = response
        stack.enter_context(redirect_stdout(StringIO()))

    def test_finder_upgrade_keeps_the_same_bridge_and_custom_settings(self):
        runpy.run_path(str(SCRIPT))
        config = plistlib.loads(self.plist.read_bytes())
        env = config["EnvironmentVariables"]
        first_id = UUID(env["OTOHA_BRIDGE_ID"])
        self.assertEqual(env["OTOHA_LAN_INTERFACE"], "en0")
        self.assertEqual(env["OTOHA_BIND"], "127.0.0.1")
        self.assertEqual(env["OTOHA_HOSTNAMES"], "family-mac.local")
        env.update(OTOHA_BIND="127.0.0.1,100.96.1.2", HK_HOST="192.168.10.3",
                   OTOHA_HOSTNAMES="family-mac.local,stereo.example.ts.net")
        self.plist.write_bytes(plistlib.dumps(config))
        self.lan = "192.168.10.40"
        runpy.run_path(str(SCRIPT))
        updated = plistlib.loads(self.plist.read_bytes())["EnvironmentVariables"]
        self.assertEqual(UUID(updated["OTOHA_BRIDGE_ID"]), first_id)
        self.assertEqual(updated["HK_HOST"], env["HK_HOST"])
        self.assertEqual(updated["OTOHA_BIND"], env["OTOHA_BIND"])
        self.assertIn("stereo.example.ts.net", updated["OTOHA_HOSTNAMES"].split(","))
        self.connection.assert_called_with(self.lan, 3770, timeout=1)
        self.run.assert_called_with(["open", "http://family-mac.local:3770"], check=True)

    def test_no_home_network_leaves_existing_installation_alone(self):
        runpy.run_path(str(SCRIPT))
        installed = self.plist.read_bytes()
        self.lan = ""
        self.run.reset_mock()
        with self.assertRaisesRegex(SystemExit, "home Wi-Fi"):
            runpy.run_path(str(SCRIPT))
        self.assertEqual(self.plist.read_bytes(), installed)
        self.assertFalse(any(call.args[0][0] == "launchctl" for call in self.run.call_args_list))
