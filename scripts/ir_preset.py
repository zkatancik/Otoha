"""The HK 3770 discrete Power On preset shared by the IR transports."""

# IRDB: NEC1, device 128, subdevice 112, function 192 and its complement.
POWER_ON_BYTES = (128, 112, 192, 192 ^ 0xFF)


def power_on_nec_hex():
    # Tasmota takes an MSB-first string. NEC sends each address/command byte LSB-first.
    wire_bits = "".join(format(octet, "08b")[::-1] for octet in POWER_ON_BYTES)
    return f"0x{int(wire_bits, 2):08X}"


def power_on_pulses():
    pulses = [9024, 4512]
    for octet in POWER_ON_BYTES:
        for bit in range(8):
            pulses.extend((564, 1692 if octet & (1 << bit) else 564))
    pulses.append(564)
    pulses.append(108000 - sum(pulses))
    return pulses
