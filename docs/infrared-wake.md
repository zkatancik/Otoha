# Power on a receiver with infrared

When a receiver disconnects from the home network in standby, Otoha can send Power On through a compatible IR blaster. The blaster receives the command over Wi-Fi and sends infrared light to the receiver’s front sensor, just like the original remote. Other controls go directly from your phone to the awake device.

1. Select your receiver and tap **Connect**. On an eligible model, choose **Connect an IR blaster**. Choose **Not now** if Wi-Fi already wakes your receiver or you want to decide later. To return, open **Power → Infrared wake**.
2. Set up the blaster on your home network using the manufacturer’s app. Place it within sight of the receiver. For BroadLink, turn off **Lock device** in its app.
3. Tap **Find a blaster**. When multiple blasters appear, choose the one beside this receiver. With multicast discovery enabled, the HK 3700 and HK 3770 also offer a separate Global Caché search, which can take about a minute.
4. For an **HK 3700 or HK 3770**, Otoha uses the shared handset’s built-in On signal. For an **AVR 170/1700, 370/3700 or 151S/1510S**, use a BroadLink RM infrared model and the original handset. Select AVR mode on the handset if available. Point it at the blaster, tap **Learn Power On**, and press **On** once when the app is listening.
5. After linking, tap **Power on** when you want to wake the receiver. The iPhone stores the blaster and any learned signal for that receiver. Setup itself sends no power command.

The AVR offer includes the corresponding catalogued regional and paired model names. Firmware and standby settings affect Wi-Fi power-on. [Standby behavior by model](standby-wake.md)

## Blasters for the shared HK 3700 and HK 3770 preset

| Blaster | What to check |
| --- | --- |
| BroadLink RM mini / pro and RM4 infrared models | Switch off **Lock device** in the BroadLink app. |
| IRKit | Join the blaster to your home Wi-Fi. |
| Nature Remo | Use a model with the local API. The Remo nano is cloud-only. |
| Tasmota IR | Enable Bonjour service advertising and configure an IRsend output. |
| Global Caché iTach IP2IR / WF2IR and Flex IR (multicast builds) | Attach an emitter and select IR mode for the first output. |
