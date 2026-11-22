# Wake the HK 3770 from your iPhone

Try a volume step from Otoha while the HK 3770 is awake, then put it in standby and try **Power on** over the same Wi-Fi. If it wakes, setup is complete. If only the original handset wakes it, a Wi-Fi infrared blaster can send the same On signal. Volume, inputs, and other receiver controls work directly from the phone.

1. Set up the blaster on your home Wi-Fi using the manufacturer’s phone app. Point its emitter at the stereo’s front sensor.
2. On the linked HK 3770 remote, open **Power → Power on troubleshooting → Wi-Fi wake failed, but the handset worked → Find and link a blaster**. In builds with multicast discovery, for Global Caché choose **Find a Global Caché iTach or Flex** and keep the app open for up to a minute.
3. A single match is linked automatically. If several appear, choose the blaster near the stereo. Setup only checks the connection.
4. Tap **Power on** when you want to wake the stereo. Otoha remembers the blaster for that receiver on this iPhone.

| Blaster | What to check |
| --- | --- |
| BroadLink RM mini / pro and RM4 infrared models | Switch off **Lock device** in the BroadLink app. |
| IRKit | Join the blaster to your home Wi-Fi. |
| Nature Remo | Use a model with the local API. The Remo nano is cloud-only. |
| Tasmota IR | Enable Bonjour service advertising and configure an IRsend output. |
| Global Caché iTach IP2IR / WF2IR and Flex IR (multicast builds) | Attach an emitter and select IR mode for the first output. |
