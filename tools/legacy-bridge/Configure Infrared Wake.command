#!/usr/bin/env python3
"""Set the home bridge's IR wake webhook without transmitting a power command."""
import getpass
import os
from pathlib import Path
import sys
import tempfile
from urllib.parse import urlsplit

print("Paste the local webhook that sends the HK 3770's discrete Power On command.")
url = getpass.getpass("Webhook URL (hidden): ").strip()
try:
    endpoint = urlsplit(url)
    valid = (
        endpoint.scheme in ("http", "https") and endpoint.hostname and endpoint.port != 0
        and endpoint.username is None and endpoint.password is None and not endpoint.fragment
        and not any(c.isspace() for c in url)
    )
except ValueError:
    valid = False
if not valid:
    sys.exit("Enter a complete HTTP or HTTPS webhook URL.")
folder = Path(os.environ.get("OTOHA_DATA") or Path.home() / ".config" / "otoha")
folder.mkdir(mode=0o700, parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(mode="w", dir=folder, delete=False) as config:
    config.write(url + "\n")
os.replace(config.name, folder / "ir-wake-url")
print("Saved. Open Power in Otoha and look for Infrared bridge under Power on.")
