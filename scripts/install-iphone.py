#!/usr/bin/env python3
"""Build, sign, install and open Otoha on a connected iPhone."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
print("Looking for a connected iPhone…", flush=True)
try:
    devices = json.loads(subprocess.check_output(["xcrun", "xcdevice", "list", "--timeout", "6"]))
except (OSError, ValueError, subprocess.CalledProcessError):
    sys.exit("Building Otoha from source requires Xcode 27.1 or newer.")
phones = [
    d for d in devices
    if d.get("available") and not d.get("simulator")
    and d.get("platform") == "com.apple.platform.iphoneos"
    and d.get("modelCode", "").startswith("iPhone")
]
if not phones:
    sys.exit("Connect and unlock your iPhone, trust this Mac, then open this installer again.")
if len(phones) == 1:
    phone = phones[0]
else:
    for n, item in enumerate(phones, 1):
        print(f"{n}. {item['name']}")
    choice = input("Select your iPhone by number: ").strip()
    if not choice.isdecimal() or not 1 <= int(choice) <= len(phones):
        sys.exit("No iPhone selected.")
    phone = phones[int(choice) - 1]
device = phone["identifier"]
print(f"Installing Otoha on {phone['name']}. Keep the iPhone unlocked.", flush=True)
try:
    with tempfile.TemporaryDirectory(prefix="otoha-install-") as build:
        subprocess.run([
            "xcodebuild", "-quiet", "-project", str(root / "ios/Otoha.xcodeproj"),
            "-scheme", "Otoha", "-configuration", "Release", "-destination", f"id={device}",
            "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            "-derivedDataPath", build, "build",
        ], check=True)
        app = Path(build) / "Build/Products/Release-iphoneos/Otoha.app"
        subprocess.run(["xcrun", "devicectl", "device", "install", "app", "--device", device, str(app)], check=True)
    subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--device", device, "com.zkatancik.otoha"], check=True)
except subprocess.CalledProcessError:
    sys.exit("Xcode could not finish. Follow any trust, signing, or Developer Mode prompt on your Mac or iPhone.")
print("Otoha is installed. Turn on your receiver, open Find my stereo on your iPhone, and choose its name.")
