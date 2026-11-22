"""Discover Global Caché iTach and Flex IR outputs and drive the first emitter."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import ipaddress
import json
import re
import socket
import struct
import subprocess
import sys
import time

from ir_preset import power_on_pulses
from ir_network import peer_mac

MODELS = {
    "itachip2ir": "iTach IP2IR", "itachwf2ir": "iTach WF2IR",
    "itachflexethernet": "iTach Flex Ethernet", "itachflexethernetpoe": "iTach Flex PoE",
    "itachflexwifi": "iTach Flex WiFi",
}


def beacon(packet, host):
    if len(packet) > 2048 or not packet.startswith(b"AMXB"):
        return None
    fields = dict(re.findall(r"<-([\w/-]+)=([^<>]*)>", packet.decode("ascii", "replace")))
    model = MODELS.get(fields.get("Model", "").lower())
    mac = re.fullmatch(r"GlobalCache_([\dA-Fa-f]{12})", fields.get("UUID", ""))
    if fields.get("Make") == "GlobalCache" and model and mac and fields.get("I/O_Class", "IR") == "IR":
        return {"kind": "itach", "model": "Global Caché " + model,
                "mac": mac[1].lower(), "host": host}


def discover(interfaces):
    devices = {}
    networks = [ipaddress.IPv4Interface(cidr) for cidr in interfaces]
    group = socket.inet_aton("239.255.250.250")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        listener.bind(("", 9131))
        joined = []
        for interface in networks:
            try:
                membership = struct.pack("4s4s", group, interface.ip.packed)
                listener.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
                joined.append(interface.network)
            except OSError:
                continue
        if not joined:
            raise ValueError("Allow the home bridge to access your local network and search again.")
        # An iTach advertises at random intervals of up to 60 seconds.
        deadline = time.monotonic() + 63
        while time.monotonic() < deadline:
            listener.settimeout(max(0.001, deadline - time.monotonic()))
            try:
                packet, (host, _) = listener.recvfrom(2049)
            except socket.timeout:
                break
            if any(ipaddress.IPv4Address(host) in network for network in joined):
                device = beacon(packet, host)
                if device and len(devices) < 64:
                    devices[device["mac"]] = device
    with ThreadPoolExecutor(max_workers=8) as pool:
        return [device for device in pool.map(available_output, devices.values()) if device]


def available_output(device):
    # The Flex beacon can also describe a serial or sensor cable on older firmware.
    if "Flex" in device["model"]:
        try:
            operate(device["host"], device["mac"], False)
        except (ValueError, OSError, subprocess.TimeoutExpired):
            return None
    return device


def exchange(connection, command):
    connection.sendall(command.encode("ascii") + b"\r")
    reply = bytearray()
    while b"\r" not in reply and len(reply) < 1024:
        part = connection.recv(512)
        if not part:
            break
        reply.extend(part)
    line, terminator, _ = bytes(reply).partition(b"\r")
    return line if terminator else b""


def operate(host, mac, transmit):
    with socket.create_connection((host, 4998), timeout=1.5) as connection:
        if peer_mac(host) != mac:
            raise ValueError("The iTach address changed. Forget the blaster and search again.")
        mode = exchange(connection, "get_IR,1:1")
        if mode not in (b"IR,1:1,IR", b"IR,1:1,IR_BLASTER", b"IR,1:1,IRTRIPORT", b"IR,1:1,IRTRIPORT_BLASTER"):
            raise ValueError("Connect an IR emitter and configure iTach output 1 for its cable.")
        if transmit:
            cycles = ",".join(str(round(pulse * 38000 / 1000000)) for pulse in power_on_pulses())
            if exchange(connection, "sendir,1:1,1,38000,1,1," + cycles) != b"completeir,1:1,1":
                raise ValueError("The iTach did not confirm the Power On transmission.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("discover", "check", "send"))
    parser.add_argument("--interface", action="append", default=[])
    parser.add_argument("--address", type=ipaddress.IPv4Address)
    parser.add_argument("--mac")
    args = parser.parse_args()
    try:
        if args.operation == "discover":
            print(json.dumps(discover(args.interface)))
        else:
            operate(str(args.address), args.mac, args.operation == "send")
    except ValueError as error:
        sys.exit(str(error))
    except (OSError, subprocess.TimeoutExpired):
        sys.exit("The bridge could not reach the iTach. Check its network connection and power.")
