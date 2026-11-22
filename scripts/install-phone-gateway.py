"""Install Otoha's authenticated tunnel origin as an independent macOS login service."""
import argparse
import ipaddress
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bind", default="127.0.0.1")
args = parser.parse_args()
ip = ipaddress.ip_address(args.bind)
if ip.version != 4 or not ip.is_private or ip.is_unspecified:
    parser.error("Choose the Mac's local IPv4 address.")
node = shutil.which("node")
if not node:
    parser.error("Node.js 22 or later is required.")
root = Path(__file__).resolve().parents[1]
label = "com.otoha.phone-gateway"
logs = Path.home() / "Library/Logs/Otoha"
logs.mkdir(parents=True, exist_ok=True)
plist = Path.home() / "Library/LaunchAgents" / (label + ".plist")
plist.parent.mkdir(parents=True, exist_ok=True)
settings = dict(Label=label, ProgramArguments=[node,str(root / "server/phone-gateway.js")],
                WorkingDirectory=str(root), RunAtLoad=True, KeepAlive=True, ThrottleInterval=10,
                EnvironmentVariables={"OTOHA_PHONE_BIND":args.bind}, StandardOutPath=str(logs / "phone.log"),
                StandardErrorPath=str(logs / "phone-error.log"))
temp = plist.with_suffix(".tmp")
temp.write_bytes(plistlib.dumps(settings))
temp.chmod(0o600)
temp.replace(plist)
domain = f"gui/{os.getuid()}"
if subprocess.run(["launchctl","print",domain + "/" + label],capture_output=True).returncode == 0:
    subprocess.run(["launchctl","bootout",domain + "/" + label],check=True)
subprocess.run(["launchctl","bootstrap",domain,str(plist)],check=True)
