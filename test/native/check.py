"""Exercise the actual Swift remote against fixtures bound only to this computer's LAN address."""
import http.server
from pathlib import Path
import shutil
import socket
import socketserver
import struct
import subprocess
import tempfile
import threading

root = Path(__file__).resolve().parents[2]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as route:
    route.connect(("239.255.255.250", 1900))
    host = route.getsockname()[0]

frames = []
learned_signal = bytes.fromhex("26 00 06 00 10 11 20 21 40 41")


class Descriptor(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        state = self.server.power_state.read_text()
        if state == "off":
            self.send_error(503)
            return
        body = b"<root><device><manufacturer>Harman Kardon</manufacturer><modelName>HK 3770</modelName><friendlyName>Test &amp; Stereo</friendlyName><UDN>uuid:otoha-test</UDN></device></root>"
        if self.path == "/avr.xml":
            body = body.replace(b"HK 3770", b"AVR 170").replace(b"otoha-test", b"otoha-avr")
        elif state == "other":
            body = body.replace(b"otoha-test", b"other-stereo")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Receiver(socketserver.StreamRequestHandler):
    def handle(self):
        while line := self.rfile.readline():
            assert line.lower() == b"post avr http/1.1\r\n"
            headers = {}
            while (line := self.rfile.readline()) != b"\r\n":
                name, value = line.decode().split(":", 1)
                headers[name] = value.strip()
            body = self.rfile.read(int(headers["Content-Length"])).decode()
            assert body.endswith("</control></common></avr></harman>")
            key = body.split("<name>")[1].split("</name>")[0]
            if key == "heart-alive":
                if self.server.power_state.read_text() in ("off", "booting"):
                    return
                self.wfile.write(b"<harman><avr><common><status><name>heart-")
                self.wfile.write(b"alive</name></status></common></avr></harman>")
            else:
                frames.append((key, body.split("<para>")[1].split("</para>")[0]))


class Blaster(socketserver.DatagramRequestHandler):
    key = bytes.fromhex("097628343fe99e23765c1513accf8b02")
    iv = "562e17996d093d28ddb3ba695a2e6f58"

    def crypt(self, data, key, decrypt=False):
        return subprocess.check_output(["/usr/bin/openssl", "enc", "-aes-128-cbc", "-K", key.hex(),
                                       "-iv", self.iv, "-nopad", "-d" if decrypt else "-e"], input=data)

    def handle(self):
        data = self.packet
        if data[38] == 6:
            reply = bytearray(128)
            reply[52:54] = struct.pack("<H", self.server.product)
            reply[58:64] = self.server.mac[::-1]
        else:
            op = data[38]
            assert struct.unpack_from("<H", data, 32)[0] == (0xbeaf + sum(data) - sum(data[32:34])) % 65536
            reply = bytearray(56)
            reply[:8] = data[:8]
            if op == 0x65:
                assert self.crypt(data[56:], self.key, True)[4:20] == b"1" * 16
                reply.extend(self.crypt(bytes(4) + bytes(range(16)) + bytes(12), self.key))
            else:
                assert op == 0x6a
                payload = self.crypt(data[56:], bytes(range(16)), True)
                extended = self.server.product == 0x51da
                if extended:
                    size, = struct.unpack_from("<H", payload)
                    assert 4 <= size <= len(payload) - 2
                    payload = payload[2:2+size]
                action, = struct.unpack_from("<I", payload)
                self.server.actions.append(action)
                answer = struct.pack("<I", action)
                if action == 2:
                    count, = struct.unpack_from("<H", payload, 6)
                    self.server.sent.append(payload[4:8+count])
                elif action == 3:
                    self.server.polls = 0
                else:
                    assert action == 4
                    self.server.polls += 1
                    if self.server.polls <= 2:
                        struct.pack_into("<h", reply, 34, [-5, -10][self.server.polls-1])
                    elif self.server.bad_capture:
                        answer += bytes.fromhex("b2 00 04 00 11 22 33 44")
                        self.server.bad_capture = False
                    else:
                        answer += learned_signal
                if extended:
                    answer = struct.pack("<H", len(answer)) + answer
                reply.extend(self.crypt(answer + bytes(-len(answer) % 16), bytes(range(16))))
            struct.pack_into("<H", reply, 32, (0xbeaf + sum(reply)) % 65536)
        self.wfile.write(reply)


class TCPFixture(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class RMFixture(socketserver.UDPServer):
    def __init__(self, product, mac):
        super().__init__((host, 0), Blaster)
        self.product = product
        self.mac = bytes.fromhex(mac)
        self.sent = []
        self.actions = []
        self.bad_capture = product == 0x51da


with tempfile.TemporaryDirectory() as folder, http.server.ThreadingHTTPServer((host, 0), Descriptor) as web, \
        TCPFixture((host, 10025), Receiver) as stereo, RMFixture(0x2737, "001122334455") as mini, \
        RMFixture(0x51da, "0123456789ab") as rm4:
    power_state = Path(folder) / "power-state"
    power_state.write_text("on")
    stereo.power_state = web.power_state = power_state
    for server in (web, stereo, mini, rm4):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    files = ["HarmanProtocol", "HarmanNetwork", "LocalNetwork", "BroadLink", "LocalInfrared", "Remote"]
    binary = Path(folder) / "check"
    shutil.copy(root / "ios/Otoha/receiver-profiles.json", folder)
    subprocess.run(["xcrun", "swiftc", "-o", str(binary), *[str(root / f"ios/Otoha/{name}.swift") for name in files],
                    str(Path(__file__).with_name("DirectRemoteCheck.swift"))], check=True)
    subprocess.run([str(binary), host, str(web.server_port), str(mini.server_address[1]), str(rm4.server_address[1]),
                    str(power_state)], check=True, timeout=45)
    assert frames == [("volume-up", ""), ("source-selection", "USB"), ("source-selection", "iPod"),
                      ("harman_volume", ""), ("harman_volume", ""), ("volume-down", ""), ("power-on", "")], frames
    import sys
    sys.path.insert(0, str(root / "scripts"))
    from ir_preset import power_on_pulses
    wave = bytearray()
    for pulse in power_on_pulses():
        ticks = int(pulse / 32.84)
        wave.extend(bytes([ticks]) if ticks < 256 else b"\0" + struct.pack(">H", ticks))
    preset = bytes([0x26, 0]) + struct.pack("<H", len(wave)) + wave
    assert mini.sent == [preset, learned_signal] and rm4.sent == [learned_signal]
    assert mini.actions == [2, 3, 4, 4, 4, 2]
    assert rm4.actions == [3, 4, 4, 4, 3, 4, 4, 4, 2]
