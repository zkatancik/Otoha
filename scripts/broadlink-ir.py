"""Configure and send the HK 3770's discrete Power On signal through a BroadLink RM."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import broadlink
from broadlink import exceptions as bl_errors
from broadlink.remote import pulses_to_data
from ir_preset import power_on_pulses


class SetupError(Exception):
    pass


def is_remote(remote):
    return all(hasattr(remote, method) for method in ("enter_learning", "check_data", "send_data"))


def discover(interfaces):
    def scan(interface):
        network = ipaddress.IPv4Interface(interface)
        try:
            return broadlink.discover(timeout=2, local_ip_address=str(network.ip),
                                      discover_ip_address=str(network.network.broadcast_address))
        except (OSError, bl_errors.NetworkTimeoutError):
            return []

    with ThreadPoolExecutor(max_workers=8) as pool:
        return [{"kind": "broadlink", "host": device.host[0], "mac": device.mac.hex(),
                 "model": f"{device.manufacturer} {device.model}"}
                for devices in pool.map(scan, interfaces) for device in devices if is_remote(device)]


def connect(address, expected_mac=None):
    ip = ipaddress.IPv4Address(address)
    home_networks = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    if not any(ip in ipaddress.IPv4Network(network) for network in home_networks):
        raise SetupError("Enter the BroadLink's home LAN IPv4 address.")
    remote = broadlink.hello(str(ip), timeout=1.5)
    if not is_remote(remote):
        raise SetupError("That device did not identify itself as a BroadLink infrared remote.")
    if expected_mac is not None and remote.mac.hex() != expected_mac:
        raise SetupError("The device at this address has changed. Run blaster setup again.")
    remote.timeout = 1.5
    if remote.is_locked:
        raise SetupError("BroadLink's device lock is on. Open the physical hub's settings in the BroadLink app and switch off Lock device.")
    remote.auth()
    return remote


def write_setting(path, text):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        output.write(text + "\n")
    os.replace(output.name, path)


def choose_remote():
    print("Looking for BroadLink remotes on your home Wi-Fi…", flush=True)
    devices = {d.mac.hex(): d for d in broadlink.discover(timeout=4) if is_remote(d)}
    choices = list(devices.values())
    if not choices:
        raise SetupError("Turn on your blaster, join it to home Wi-Fi in the BroadLink app, then run setup again.")
    if len(choices) == 1:
        return choices[0]
    for index, device in enumerate(choices, 1):
        print(f"{index}. {device.model} (ID ending in {device.mac.hex()[-6:]})")
    choice = input("Choose the blaster by your stereo, or press Return to cancel: ").strip()
    if not choice.isdecimal() or not 1 <= int(choice) <= len(choices):
        raise SetupError("No blaster selected.")
    return choices[int(choice) - 1]


def configure(directory, address):
    if address:
        remote = connect(address)
    else:
        found = choose_remote()
        address = found.host[0]
        remote = connect(address, found.mac.hex())
    settings = {"host": address, "mac": remote.mac.hex()}
    write_setting(directory / "broadlink-power-on.json", json.dumps(settings))
    write_setting(directory / "ir-wake-url", "broadlink:power-on")
    print(f"Linked {remote.model}. In Otoha, open Power and tap Power on.")


def send_saved(directory):
    try:
        settings = json.loads((directory / "broadlink-power-on.json").read_text())
    except FileNotFoundError:
        raise SetupError("Run Set Up BroadLink Wake on the Mac mini first.")
    send(settings["host"], settings["mac"])


def send(address, mac):
    remote = connect(address, mac)
    # Stay below the library's retry interval for a single transmission.
    remote.timeout = 0.9
    remote.send_data(pulses_to_data(power_on_pulses()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("configure", "send", "check", "discover"))
    parser.add_argument("--interface", action="append", default=[])
    parser.add_argument("--mac")
    parser.add_argument("--address")
    parser.add_argument("--directory", type=Path, default=Path(os.environ.get("OTOHA_DATA") or Path.home() / ".config/otoha"))
    args = parser.parse_args()
    if not args.address and (args.operation == "check" or (args.operation == "send" and args.mac)):
        parser.error("This operation needs a previously discovered blaster address.")
    if args.operation == "configure":
        configure(args.directory, args.address)
    elif args.operation == "discover":
        print(json.dumps(discover(args.interface)))
    elif args.operation == "send":
        if args.mac:
            send(args.address, args.mac)
        else:
            send_saved(args.directory)
    else:
        remote = connect(args.address, args.mac)
        print(f"BroadLink discovery and authorization succeeded at {args.address} ({remote.model}).")


if __name__ == "__main__":
    try:
        main()
    except SetupError as error:
        sys.exit(str(error))
    except bl_errors.AuthenticationError:
        sys.exit("BroadLink rejected local authorization. Check Lock device in the physical hub's settings.")
    except (bl_errors.NetworkTimeoutError, OSError):
        sys.exit("The Mac could not reach the BroadLink or read its local configuration.")
    except (bl_errors.BroadlinkException, ValueError, KeyError):
        sys.exit("BroadLink did not accept this operation. Check the hub and the saved Power On command.")
