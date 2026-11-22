"""Install the user-owned Otoha bridge on this Mac and keep it running at login."""
import argparse
import http.client
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time
from uuid import uuid4

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--receiver", help="Optional receiver LAN IPv4 address to include during discovery")
parser.add_argument("--lan", action="store_true", help="allow devices on the home LAN")
parser.add_argument("--tailscale", action="store_true", help="allow private access through this Mac's Tailscale IPv4 address")
parser.add_argument("--open", action="store_true", help="open the browser remote after home Wi-Fi setup")
args = parser.parse_args()
if args.open and not args.lan:
    parser.error("--open requires --lan")
if sys.platform != "darwin":
    parser.error("This login installer requires macOS. Use npm start on other systems.")
if args.receiver:
    addr = ipaddress.ip_address(args.receiver)
    if addr.version != 4 or not addr.is_private or addr.is_loopback:
        parser.error("Use the receiver's private LAN IPv4 address.")
root = Path(__file__).resolve().parents[1]
home = Path.home()
node = shutil.which("node")
if not node or int(subprocess.check_output([node, "-p", "process.versions.node.split('.')[0]"])) < 22:
    parser.error("Install Node.js 22 or later first.")
label = "com.otoha.stereo-bridge"
plist = home / "Library" / "LaunchAgents" / (label + ".plist")
previous = plistlib.loads(plist.read_bytes()).get("EnvironmentVariables", {}) if plist.exists() else {}
# The Finder shortcut can upgrade a customized installation without losing its settings.
env = dict(previous) if args.open else {}
bindings = ["127.0.0.1"]
names = []
if args.open:
    bindings += [ip for ip in previous.get("OTOHA_BIND", "").split(",")
                 if ip and ipaddress.ip_address(ip) in ipaddress.ip_network("100.64.0.0/10")]
    names += [n for n in previous.get("OTOHA_HOSTNAMES", "").split(",") if n and not n.endswith(".local")]
if args.receiver:
    env["HK_HOST"] = args.receiver
if args.lan:
    target = args.receiver or "239.255.255.250"
    route = subprocess.run(["/sbin/route", "-n", "get", target], capture_output=True, text=True)
    iface = next((line.split()[-1] for line in route.stdout.splitlines()
                  if line.strip().startswith("interface:")), None)
    lan = subprocess.run(["/usr/sbin/ipconfig", "getifaddr", iface], capture_output=True,
                         text=True).stdout.strip() if iface else ""
    home_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    if not lan or not any(ipaddress.ip_address(lan) in ipaddress.ip_network(r) for r in home_ranges):
        sys.exit("Connect your Mac to your home Wi-Fi or router, then open Set Up Otoha again.")
    local_name = subprocess.check_output(["/usr/sbin/scutil", "--get", "LocalHostName"], text=True).strip().lower() + ".local"
    names.append(local_name)
    env["OTOHA_LAN_INTERFACE"] = iface
    env["OTOHA_BRIDGE_ID"] = previous.get("OTOHA_BRIDGE_ID") or str(uuid4())
if args.tailscale:
    cli = shutil.which("tailscale")
    if not cli:
        parser.error("Install and sign in to Tailscale first.")
    ts = json.loads(subprocess.check_output([cli, "status", "--json"]))
    if ts.get("BackendState") != "Running":
        parser.error("Connect Tailscale on this Mac first.")
    bindings.append(next(ip for ip in ts["TailscaleIPs"] if ":" not in ip))
    dns = ts["Self"]["DNSName"].rstrip(".")
    if dns:
        names.append(dns)
env["OTOHA_BIND"] = ",".join(bindings)
env["OTOHA_HOSTNAMES"] = ",".join(names)
if os.getenv("OTOHA_IR_WAKE_URL"):
    env["OTOHA_IR_WAKE_URL"] = os.environ["OTOHA_IR_WAKE_URL"]
app = home / "Applications" / "Otoha Bridge.app"
contents = app / "Contents"
binary = contents / "MacOS" / "OtohaBridge"
binary.parent.mkdir(parents=True, exist_ok=True)
info = dict(CFBundleIdentifier=label, CFBundleName="Otoha Bridge",
            CFBundleDisplayName="Otoha Bridge", CFBundleExecutable="OtohaBridge",
            CFBundlePackageType="APPL", CFBundleVersion="2", CFBundleShortVersionString="2.0",
            LSUIElement=True, NSBonjourServices=["_otoha._tcp"],
            NSLocalNetworkUsageDescription="Otoha discovers and controls your Harman Kardon stereo on your home network.")
compiler_input = root / "scripts/mac-bridge.cc"
node_prefix = Path(node).resolve().parent.parent
libraries = sorted((node_prefix / "lib").glob("libnode.*.dylib"))
encoded = plistlib.dumps(info)
info_path = contents / "Info.plist"
if (not binary.exists() or binary.stat().st_mtime < max(compiler_input.stat().st_mtime, Path(node).stat().st_mtime)
        or not info_path.exists() or info_path.read_bytes() != encoded):
    info_path.write_bytes(encoded)
    if libraries:
        lib = libraries[0]
        subprocess.run(["xcrun", "clang++", "-Os", str(compiler_input), str(lib),
                        "-Wl,-rpath," + str(lib.parent), "-o", str(binary)], check=True)
    else:
        # Standalone Node distributions include the runtime in the executable.
        shutil.copy2(node, binary)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
subprocess.run([registrar, "-f", str(app)], check=True)
folder = home / "Library" / "LaunchAgents"
folder.mkdir(exist_ok=True)
logs = home / "Library" / "Logs" / "Otoha"
logs.mkdir(parents=True, exist_ok=True)
config = dict(Label=label, ProgramArguments=[str(binary), str(root / "server/main.js")],
              AssociatedBundleIdentifiers=[label],
              WorkingDirectory=str(root), RunAtLoad=True, KeepAlive=True,
              ThrottleInterval=10, EnvironmentVariables=env,
              StandardOutPath=str(logs/"bridge.log"), StandardErrorPath=str(logs/"bridge-error.log"))
domain = "gui/" + str(os.getuid())
tmp = plist.with_suffix(".tmp")
tmp.write_bytes(plistlib.dumps(config))
tmp.chmod(0o600)
tmp.replace(plist)
if subprocess.run(["launchctl", "print", domain + "/" + label], capture_output=True).returncode == 0:
    subprocess.run(["launchctl","bootout",domain + "/" + label], check=True)
subprocess.run(["launchctl","bootstrap",domain,str(plist)], check=True)
if args.open:
    print("Allow Otoha Bridge to find devices on your local network if your Mac asks.", flush=True)
    for _ in range(45):
        connection = http.client.HTTPConnection(lan, 3770, timeout=1)
        try:
            connection.request("GET", "/app.webmanifest", headers={"Host": local_name + ":3770"})
            response = connection.getresponse()
            if response.status == 200 and json.loads(response.read()).get("short_name") == "Otoha":
                break
        except (OSError, ValueError, http.client.HTTPException):
            pass
        finally:
            connection.close()
        time.sleep(1)
    else:
        sys.exit("Otoha could not start. Check that you are on home Wi-Fi and allow Otoha Bridge "
                 "in System Settings → Privacy & Security → Local Network, then open Set Up Otoha again.")
    subprocess.run(["open", f"http://{local_name}:3770"], check=True)
    print("Choose Locate and link in your browser. To use the same remote on your iPhone, choose Use on a phone and scan the code with Camera.")
else:
    for address in bindings + ([lan] if args.lan else []) + names:
        print(f"http://{address}:3770")
