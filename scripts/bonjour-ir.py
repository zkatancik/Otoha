"""Discover and control IRKit, Nature Remo and Tasmota infrared transmitters on the LAN."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from http.client import HTTPConnection, HTTPException
import ipaddress
import json
import re
import subprocess
import sys
import threading
import time
from urllib.parse import urlencode

from ir_network import peer_mac
from ir_preset import power_on_nec_hex, power_on_pulses

SERVICES = {"_irkit._tcp.local.": "irkit", "_remo._tcp.local.": "remo", "_http._tcp.local.": "tasmota"}
LABELS = {"irkit": "IRKit", "remo": "Nature Remo", "tasmota": "Tasmota IR"}
LAN = tuple(ipaddress.IPv4Network(cidr) for cidr in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"))
PROBE_ERRORS = (OSError, ValueError, HTTPException, subprocess.TimeoutExpired)


def request(connection, method, path, payload=None):
    body = json.dumps(payload, separators=(",", ":")) if payload is not None else None
    headers = {"X-Requested-With": "Otoha"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    connection.request(method, path, body=body, headers=headers)
    response = connection.getresponse()
    if response.status != 200:
        raise ValueError("The blaster rejected the request. Check its local API access.")
    data = response.read(32769)
    if len(data) > 32768:
        raise ValueError("Unexpected response from the blaster.")
    return data


def tasmota_command(connection, command):
    result = json.loads(request(connection, "GET", "/cm?" + urlencode({"cmnd": command})))
    if not isinstance(result, dict):
        raise ValueError("Unexpected Tasmota response.")
    return result


def has_ir_output(gpios):
    # GPIO 255 reports assigned pins, including fixed pins in the active module template.
    for pin, assignment in gpios.items():
        if not re.fullmatch(r"GPIO\d+", pin):
            continue
        names = list(assignment) + list(assignment.values()) if isinstance(assignment, dict) else [assignment]
        if any(re.fullmatch(r"(?:\d+ \()?IRsend\)?", str(name), re.I) for name in names):
            return True
    return False


def operate(kind, host, port, expected_mac=None, transmit=False):
    address = ipaddress.IPv4Address(host)
    if not any(address in net for net in LAN) or not 1 <= port <= 65535:
        raise ValueError("The blaster must be on the home LAN.")
    with closing(HTTPConnection(host, port, timeout=1.5)) as connection:
        connection.connect()
        mac = peer_mac(host)
        if not mac or not re.fullmatch(r"[0-9a-f]{12}", mac) or (expected_mac and mac != expected_mac):
            raise ValueError("The blaster’s hardware address could not be verified. Search for it again.")
        if kind == "tasmota":
            if not has_ir_output(tasmota_command(connection, "GPIO 255")):
                raise ValueError("This Tasmota device needs a configured IRsend output.")
            if transmit:
                command = {"Protocol": "NEC", "Bits": 32, "Data": power_on_nec_hex(), "Repeat": 0}
                reply = tasmota_command(connection, "IRSend " + json.dumps(command, separators=(",", ":")))
                if not any(k.lower() == "irsend" and str(v).lower() == "done" for k, v in reply.items()):
                    raise ValueError("Tasmota did not accept the infrared On command.")
        elif transmit:
            # A single frame ends at the final mark. IRKit uses half-microsecond ticks.
            pulses = power_on_pulses()[:-1]
            signal = {"format": "us", "freq": 38, "data": pulses}
            if kind == "irkit":
                signal = {"format": "raw", "freq": 38, "data": [2 * pulse for pulse in pulses]}
            request(connection, "POST", "/messages", signal)
        # Opening the advertised IRKit/Remo service verifies reachability without
        # reading /messages, which would consume a pending learned signal on IRKit.
        return {"kind": kind, "host": host, "port": port, "mac": mac, "model": LABELS[kind]}


def resolve_service(zc, service, name, interfaces):
    kind = SERVICES[service]
    info = zc.get_service_info(service, name, timeout=1100)
    if info is None or not 1 <= info.port <= 65535:
        return []
    if kind == "tasmota" and info.properties.get(b"devicetype") != b"tasmota":
        return []
    devices = []
    for host in info.parsed_addresses():
        ip = ipaddress.ip_address(host)
        if not any(ip in iface.network and ip not in (iface.ip, iface.network.network_address,
                       iface.network.broadcast_address) for iface in interfaces):
            continue
        try:
            devices.append(operate(kind, host, info.port))
        except PROBE_ERRORS:
            continue
    return devices


def discover(cidrs):
    from zeroconf import IPVersion, ServiceBrowser, ServiceStateChange, Zeroconf

    interfaces = [ipaddress.IPv4Interface(cidr) for cidr in cidrs]
    if not interfaces:
        return []
    names = {service: set() for service in SERVICES}
    lock = threading.Lock()

    def changed(zeroconf, service_type, name, state_change):
        with lock:
            entries = names[service_type]
            if state_change == ServiceStateChange.Removed:
                entries.discard(name)
            elif len(entries) < 64:
                entries.add(name)

    with Zeroconf(interfaces=[str(i.ip) for i in interfaces], ip_version=IPVersion.V4Only) as zc:
        browser = ServiceBrowser(zc, list(SERVICES), handlers=[changed])
        try:
            time.sleep(3)
            with lock:
                records = [(service, name) for service, entries in names.items() for name in entries]
            with ThreadPoolExecutor(max_workers=12) as pool:
                probes = [pool.submit(resolve_service, zc, service, name, interfaces) for service, name in records]
                return [device for probe in probes for device in probe.result()]
        finally:
            browser.cancel()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("discover", "check", "send"))
    parser.add_argument("--interface", action="append", default=[])
    parser.add_argument("--kind", choices=LABELS)
    parser.add_argument("--address")
    parser.add_argument("--port", type=int, default=80)
    parser.add_argument("--mac")
    args = parser.parse_args()
    try:
        if args.operation == "discover":
            print(json.dumps(discover(args.interface)))
        elif args.kind and args.address and args.mac:
            operate(args.kind, args.address, args.port, args.mac, args.operation == "send")
        else:
            parser.error("A linked blaster is required.")
    except ValueError as error:
        sys.exit(str(error))
    except (OSError, HTTPException, subprocess.TimeoutExpired):
        sys.exit("The bridge could not reach the blaster. Check its power and home network connection.")
