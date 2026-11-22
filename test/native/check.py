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
ir_operations = []


class Descriptor(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"<root><device><manufacturer>Harman Kardon</manufacturer><modelName>HK 3770</modelName><friendlyName>Test &amp; Stereo</friendlyName><UDN>uuid:otoha-test</UDN></device></root>"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class Receiver(socketserver.StreamRequestHandler):
    def handle(self):
        while line := self.rfile.readline():
            assert line == b"POST avr HTTP/1.1\r\n"
            headers = {}
            while (line := self.rfile.readline()) != b"\r\n":
                name, value = line.decode().split(":", 1)
                headers[name] = value.strip()
            body = self.rfile.read(int(headers["Content-Length"])).decode()
            assert body.endswith("</control></common></avr></harman>")
            key = body.split("<name>")[1].split("</name>")[0]
            if key == "heart-alive":
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
            reply[52:54] = struct.pack("<H", 0x2737)
            reply[58:64] = bytes.fromhex("554433221100")
        else:
            op = data[38]
            ir_operations.append(op)
            assert struct.unpack_from("<H", data, 32)[0] == (0xbeaf + sum(data) - sum(data[32:34])) % 65536
            reply = bytearray(56)
            reply[:8] = data[:8]
            if op == 0x65:
                assert self.crypt(data[56:], self.key, True)[4:20] == b"1" * 16
                reply.extend(self.crypt(bytes(4) + bytes(range(16)) + bytes(12), self.key))
            else:
                assert op == 0x6a
                payload = self.crypt(data[56:], bytes(range(16)), True)
                assert payload[:6] == bytes([2, 0, 0, 0, 0x26, 0])
                # Compare the transmitted signal with the independent HK 3770 preset.
                import sys
                sys.path.insert(0, str(root / "scripts"))
                from ir_preset import power_on_pulses
                wave = bytearray()
                for pulse in power_on_pulses():
                    ticks = int(pulse / 32.84)
                    wave.extend(bytes([ticks]) if ticks < 256 else b"\0" + struct.pack(">H", ticks))
                assert payload[6:8] == struct.pack("<H", len(wave)) and payload[8:8+len(wave)] == wave
                reply.extend(self.crypt(bytes(16), bytes(range(16))))
            struct.pack_into("<H", reply, 32, (0xbeaf + sum(reply)) % 65536)
        self.wfile.write(reply)


class TCPFixture(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with tempfile.TemporaryDirectory() as folder, http.server.ThreadingHTTPServer((host, 0), Descriptor) as web, \
        TCPFixture((host, 10025), Receiver) as stereo, socketserver.UDPServer((host, 0), Blaster) as ir:
    for server in (web, stereo, ir):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    files = ["HarmanProtocol", "HarmanNetwork", "LocalNetwork", "BroadLink", "LocalInfrared", "Remote"]
    binary = Path(folder) / "check"
    shutil.copy(root / "server/receiver-profiles.json", folder)
    subprocess.run(["xcrun", "swiftc", "-o", str(binary), *[str(root / f"ios/Otoha/{name}.swift") for name in files],
                    str(Path(__file__).with_name("DirectRemoteCheck.swift"))], check=True)
    subprocess.run([str(binary), host, str(web.server_port), str(ir.server_address[1])], check=True, timeout=40)
    assert frames == [("volume-up", ""), ("source-selection", "USB"), ("source-selection", "iPod"),
                      ("harman_volume", ""), ("harman_volume", "")]
    assert ir_operations == [0x65, 0x65, 0x6a]
