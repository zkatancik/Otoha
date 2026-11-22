"""Check discovery filtering and wire requests against a local HTTP blaster fixture."""
from contextlib import ExitStack
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from importlib import util
import ipaddress
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlsplit

scripts = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(scripts))
spec = util.spec_from_file_location("bonjour_ir", scripts / "bonjour-ir.py")
driver = util.module_from_spec(spec)
spec.loader.exec_module(driver)

HOST = "192.168.34.9"
MAC = "decafbad1234"


class BonjourIRTest(unittest.TestCase):
    def setUp(self):
        owner = self
        self.requests = []
        self.gpios = {"GPIO4": {"IRsend": 1056}}
        self.command_reply = {"IRSend": "Done"}
        self.status = 200

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                command = parse_qs(urlsplit(self.path).query)["cmnd"][0]
                owner.requests.append(("GET", command))
                data = owner.gpios if command == "GPIO 255" else owner.command_reply
                self.send_response(owner.status)
                self.end_headers()
                self.wfile.write(json.dumps(data).encode())

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                owner.requests.append(("POST", self.path, self.headers["X-Requested-With"], body))
                self.send_response(owner.status)
                self.end_headers()

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.addCleanup(server.server_close)
        threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True).start()
        self.addCleanup(server.shutdown)
        self.port = server.server_port

        def connection(host, port, timeout):
            self.assertEqual((host, port), (HOST, self.port))
            return HTTPConnection("127.0.0.1", port, timeout=timeout)

        stack = ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(patch.object(driver, "peer_mac", return_value=MAC))
        stack.enter_context(patch.object(driver, "HTTPConnection", side_effect=connection))

    def resolve(self, kind, *, hosts=(HOST,), properties=None):
        info = SimpleNamespace(port=self.port, properties=properties or {}, parsed_addresses=lambda: hosts)
        service = next(s for s, k in driver.SERVICES.items() if k == kind)
        return driver.resolve_service(Mock(get_service_info=Mock(return_value=info)), service,
                                      "blaster." + service, [ipaddress.IPv4Interface("192.168.34.2/24")])

    def test_advertised_remo_and_irkit_send_one_frame_in_their_own_units(self):
        for kind, units, header, one in [("irkit", "raw", 18048, 3384), ("remo", "us", 9024, 1692)]:
            with self.subTest(kind=kind):
                self.requests.clear()
                device, = self.resolve(kind, hosts=("203.0.113.4", "192.168.34.2", HOST))
                self.assertEqual((device["kind"], device["port"], device["mac"]), (kind, self.port, MAC))
                driver.operate(kind, HOST, self.port, MAC, False)
                self.assertEqual(self.requests, [])
                driver.operate(kind, HOST, self.port, MAC, True)
                request, = self.requests
                self.assertEqual(request[:3], ("POST", "/messages", "Otoha"))
                signal = request[3]
                self.assertEqual((signal["format"], signal["freq"]), (units, 38))
                timings = signal["data"]
                self.assertEqual((len(timings), timings[0]), (67, header))
                octets = [sum((timings[3 + 16*i + 2*b] == one) << b for b in range(8)) for i in range(4)]
                self.assertEqual(octets, [128, 112, 192, 63])

    def test_tasmota_filters_ordinary_http_and_receive_only_pins(self):
        self.assertEqual(self.resolve("tasmota", properties={b"devicetype": b"printer"}), [])
        self.assertEqual(self.requests, [])
        self.gpios = {"GPIO4": {"IRrecv": 1088}}
        self.assertEqual(self.resolve("tasmota", properties={b"devicetype": b"tasmota"}), [])
        self.assertEqual(self.requests, [("GET", "GPIO 255")])

    def test_tasmota_nec_and_negative_ack(self):
        device, = self.resolve("tasmota", properties={b"devicetype": b"tasmota"})
        self.assertEqual(device["kind"], "tasmota")
        driver.operate("tasmota", HOST, self.port, MAC, True)
        self.assertEqual(self.requests[:2], [("GET", "GPIO 255")] * 2)
        operation, body = self.requests[2][1].split(" ", 1)
        self.assertEqual(operation, "IRSend")
        self.assertEqual(json.loads(body), {"Protocol": "NEC", "Bits": 32, "Data": "0x010E03FC", "Repeat": 0})
        self.command_reply = {"IRSend": "Protocol not supported"}
        with self.assertRaisesRegex(ValueError, "did not accept"):
            driver.operate("tasmota", HOST, self.port, MAC, True)

    def test_identity_and_failed_http_never_report_success(self):
        for kind in driver.LABELS:
            with self.assertRaisesRegex(ValueError, "hardware address"):
                driver.operate(kind, HOST, self.port, "001122334455", True)
        self.assertEqual(self.requests, [])
        self.status = 302
        with self.assertRaisesRegex(ValueError, "rejected"):
            driver.operate("irkit", HOST, self.port, MAC, True)
        self.assertEqual(len(self.requests), 1)


if __name__ == "__main__":
    unittest.main()
