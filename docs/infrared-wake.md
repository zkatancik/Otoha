# Wake the HK 3770 from your iPhone

The stereo can turn off its network connection in standby. A Wi-Fi infrared blaster sends the same On signal as the original handset. Volume, inputs, and other receiver controls work directly from the phone with the stereo awake.

1. Set up the blaster on your home Wi-Fi using the manufacturer’s phone app. Point its emitter at the stereo’s front sensor.
2. Link your HK 3770 in Otoha. Open **Power → Set up infrared wake → Find and link a blaster**. In builds with multicast discovery, for Global Caché choose **Find a Global Caché iTach or Flex** and keep the app open for up to a minute.
3. A single match is linked automatically. If several appear, choose the blaster near the stereo. Setup only checks the connection.
4. Tap **Power on** when you want to wake the stereo. Otoha remembers the blaster for that receiver on this iPhone.

| Blaster | What to check |
| --- | --- |
| BroadLink RM mini / pro and RM4 infrared models | Switch off **Lock device** in the BroadLink app. |
| IRKit | Join the blaster to your home Wi-Fi. |
| Nature Remo | Use a model with the local API. The Remo nano is cloud-only. |
| Tasmota IR | Enable Bonjour service advertising and configure an IRsend output. |
| Global Caché iTach IP2IR / WF2IR and Flex IR (multicast builds) | Attach an emitter and select IR mode for the first output. |
