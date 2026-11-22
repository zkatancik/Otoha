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

## Link an unlisted blaster

1. Open **Power → Set up infrared wake → Not listed**. You can go straight there before searching.
2. Aim the blaster at the stereo. In its app, select the HK 3770’s **Power On** command or teach it the **On** button from the original remote. A power toggle can switch an already-on receiver off.
3. Use a local webhook that sends this one command when it receives an empty HTTP POST. The blaster can provide it directly. If it needs its own app or command format, use a home automation hub that can control it.
4. Paste the full HTTP or HTTPS URL in **Power-on webhook URL** and tap **Link blaster**. Use the local Power On link provided by your blaster or controller.
5. When you’re ready to try it, put the stereo in standby and tap **Power on**. To change the link, open **Infrared wake → Forget blaster**.

If the iPhone declines a link that uses a hostname, use the controller’s private Wi-Fi IP address in the URL. The browser bridge also accepts `.local` hostnames. Both expect the webhook to return an HTTP 2xx response.

For example, in Home Assistant create an automation with a **Webhook** trigger, enable POST and keep local-only access enabled. Set its action to send the saved On command. Save the automation and copy its local URL, including the generated webhook ID. [Home Assistant webhook instructions](https://www.home-assistant.io/triggers/webhook/)
