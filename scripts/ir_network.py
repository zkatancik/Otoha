"""Read the hardware address of a connected peer on the bridge's LAN."""
from pathlib import Path
import re
import subprocess
import sys


def peer_mac(host):
    # A live connection populates the local neighbor table before this lookup.
    if sys.platform.startswith("linux"):
        for row in Path("/proc/net/arp").read_text().splitlines()[1:]:
            fields = row.split()
            if len(fields) >= 4 and fields[0] == host and int(fields[2], 16) & 2:
                return fields[3].replace(":", "").lower()
    elif sys.platform == "darwin":
        row = subprocess.run(["/usr/sbin/arp", "-n", host], capture_output=True,
                             text=True, timeout=1).stdout
        match = re.search(r" at ((?:[a-f\d]{1,2}:){5}[a-f\d]{1,2}) ", row, re.I)
        if match:
            return "".join(part.zfill(2) for part in match[1].lower().split(":"))
