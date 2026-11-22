"""Exercise the actual iTach driver with recorded-format protocol fixtures."""
from importlib import util
from pathlib import Path
import sys
import unittest
from unittest.mock import MagicMock, patch

scripts = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(scripts))
spec = util.spec_from_file_location("itach", scripts / "itach-ir.py")
itach = util.module_from_spec(spec)
spec.loader.exec_module(itach)


class ITachTest(unittest.TestCase):
    def test_beacon_uses_sender_and_only_accepts_ir_products(self):
        packet = (b"AMXB<-UUID=GlobalCache_000C1E024239><-Make=GlobalCache>"
                  b"<-Model=iTachWF2IR><-Config-URL=http://example.org>")
        result = itach.beacon(packet, "192.168.9.17")
        self.assertEqual(result, {"host": "192.168.9.17", "model": "Global Caché iTach WF2IR",
                                  "kind": "itach", "mac": "000c1e024239"})
        self.assertIsNone(itach.beacon(packet.replace(b"WF2IR", b"WF2CC"), "192.168.9.17"))
        self.assertIsNone(itach.beacon(packet.replace(b"000C1E", b"bogus"), "192.168.9.17"))

    def test_check_and_single_acknowledged_power_on(self):
        connection = MagicMock()
        connection.recv.side_effect = [b"IR,1:1,IR\r", b"IR,1:1,IR\r", b"completeir,", b"1:1,1\r"]
        with patch.object(itach.socket, "create_connection") as connect, patch.object(itach, "peer_mac", return_value="aabbccddeeff"):
            connect.return_value.__enter__.return_value = connection
            itach.operate("192.168.9.17", "aabbccddeeff", False)
            connection.sendall.assert_called_once_with(b"get_IR,1:1\r")
            itach.operate("192.168.9.17", "aabbccddeeff", True)
        self.assertEqual(connection.sendall.call_count, 3)
        command = connection.sendall.call_args.args[0].decode("ascii").strip().split(",")
        self.assertEqual(command[:6], ["sendir", "1:1", "1", "38000", "1", "1"])
        cycles = list(map(int, command[6:]))
        self.assertEqual(len(cycles), 68)
        self.assertEqual(cycles[:2], [343, 171])
        data = [sum((cycles[3 + 2 * (n * 8 + bit)] > 40) << bit for bit in range(8)) for n in range(4)]
        self.assertEqual(data, [128, 112, 192, 63])

    def test_flex_requires_an_ir_output_before_becoming_a_candidate(self):
        prefix = b"AMXB<-UUID=GlobalCache_000C1E024239><-Make=GlobalCache>"
        for model in (b"iTachFlexWiFi", b"iTachFlexEthernet", b"iTachFlexEthernetPoE"):
            packet = prefix + b"<-Model=" + model + b">"
            device = itach.beacon(packet, "192.168.9.17")
            self.assertIn("Flex", device["model"])
            self.assertIsNone(itach.beacon(packet + b"<-I/O_Class=SERIAL>", "192.168.9.17"))
            with patch.object(itach, "peer_mac", return_value=device["mac"]), patch.object(itach.socket, "create_connection") as connect:
                connection = connect.return_value.__enter__.return_value
                connection.recv.side_effect = [b"IR,1:1,SERIAL\r", b"IR,1:1,IRTRIPORT_BLASTER\r"]
                self.assertIsNone(itach.available_output(device))
                self.assertEqual(itach.available_output(device), device)
                self.assertEqual([c.args for c in connection.sendall.call_args_list], [(b"get_IR,1:1\r",)] * 2)

    def test_changed_address_input_mode_or_missing_ack_fails_closed(self):
        for mac, replies, expected_commands in [
            ("different", [], 0),
            ("same", [b"IR,1:1,SENSOR\r"], 1),
            ("same", [b"IR,1:1,IR\r", b"busyIR,1:1,1\r"], 2),
        ]:
            with self.subTest(mac=mac, replies=replies), patch.object(itach, "peer_mac", return_value=mac), patch.object(itach.socket, "create_connection") as connect:
                connection = connect.return_value.__enter__.return_value
                connection.recv.side_effect = replies
                with self.assertRaises(ValueError):
                    itach.operate("192.168.9.17", "same", True)
                self.assertEqual(connection.sendall.call_count, expected_commands)


if __name__ == "__main__":
    unittest.main()
