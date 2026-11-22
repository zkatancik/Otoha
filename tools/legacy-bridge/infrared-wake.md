# Legacy browser and bridge infrared setup

# Turn on the HK 3770 with infrared

In Otoha on iPhone, open **Power → Power on**. A linked blaster lets the phone send the On command over your home Wi-Fi. When the receiver wakes and its network control service responds, Otoha shows **Connected**.

## Find and link a blaster

The HK 3770 can shut down its Ethernet controls in standby. An IR blaster on the home network sends the handset’s discrete **On** signal to the front sensor. An already-on receiver stays on.

Power the blaster, join it to your home network, and aim the emitter at the receiver’s front sensor.

| Blaster | Before you search |
| --- | --- |
| BroadLink RM infrared remote | Join Wi-Fi and turn off **Lock device** in the BroadLink app. [BroadLink discovery](https://github.com/mjg59/python-broadlink#discovery) |
| Global Caché iTach IP2IR or WF2IR | Plug a standard emitter into output 1 and set that output to **IR**. [iTach specifications](https://www.globalcache.com/files/docs/API-iTach.pdf) |
| Global Caché iTach Flex WiFi, Ethernet or PoE | Attach a Flex Link IR emitter or blaster cable and select its matching IR mode. With a tri-port cable, put the receiver’s emitter on the first output. [Flex TCP API](https://www.globalcache.com/files/releases/flex-16/API-Flex_TCP_1.6.pdf) |
| IRKit | Use an IRKit joined to Wi-Fi that advertises its Bonjour service. [IRKit local API](https://getirkit.com/en/) |
| Nature Remo | Use a model that offers the Remo local API on Wi-Fi. The Remo nano is cloud-only. [Nature device support](https://developer.nature.global/en/) · [Remo local API](https://local-swagger.nature.global/) |
| Tasmota IR transmitter | Use firmware with an **IRsend** pin, NEC transmission and HTTP service advertising over mDNS (Bonjour). Otoha needs access to its local HTTP commands without credentials. For a password-protected device, use the webhook option below. [Tasmota IR](https://tasmota.github.io/docs/Tasmota-IR/) · [Tasmota service advertisement](https://github.com/arendst/Tasmota/blob/development/tasmota/tasmota_support/support_network.ino) |

1. With your HK 3770 linked to Otoha, open **Power → Set up infrared wake** on iPhone or in the browser. Read the guide, then tap **Find and link a blaster**. Closing the guide before that button leaves discovery off.
2. On iPhone, use **Find a Global Caché iTach or Flex** for those models and allow about a minute. In the browser, the bridge searches all supported families together. Its first search may need Python 3.9 or newer and internet access to install optional drivers. A single match is checked and saved automatically. If several hubs answer, select the one near your receiver by model and the last six digits of its hardware ID.
3. When the blaster shows as linked, use **Power → Power on** when you want to wake the stereo. Setup itself sends no IR. To return to network wake or move to another hub, choose **Power → Infrared wake → Forget blaster**. If the router changes the hub’s address, forget it and search again.

Searches run only on request. A receiver keeps its own saved blaster across bridge restarts. If the bridge already has a BroadLink or webhook configured for that receiver, Otoha shows it under **Infrared wake**. A controller with a different discovery protocol can use the webhook instructions below.

## Restore the original BroadLink installation

Keep the hub powered and within sight of the receiver’s front IR sensor. The Mac mini must be awake and running Otoha.

To restore this setup on the Mac mini:

1. In the BroadLink app, open the physical hub and turn off **Lock device** in its settings.
2. Double-click **Set Up BroadLink Wake.command**. It connects to the hub, records its hardware address, and configures Otoha to use the built-in HK 3770 signal. Setup takes effect immediately. It requires only the hub and the Mac.
3. In the browser remote, open **Power** and tap **Power on** to try the restored bridge configuration.

If the hub moves or stops responding, double-click **Set Up BroadLink Wake.command** again. It finds BroadLink remotes on your home Wi-Fi. If more than one appears, choose the one by your stereo. If Otoha reports that the hub accepted a request but the receiver stays asleep, check the sightline and that the receiver has standby power.

The preset uses NEC1 device 128, subdevice 112, function 192, published as **POWER ON**. The HK handset has separate On and Off buttons. [Published Harman Kardon receiver commands](https://github.com/probonopd/irdb/blob/master/codes/Harman%20Kardon/Receiver/128%2C112.csv) · [HK 3770 owner’s manual](https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=9)

## Link a blaster under Not listed

Open **Power → Set up infrared wake → Not listed** on iPhone or in the browser. You can go straight here or use it after a search. You’ll need an IR blaster that can send a saved command and either a local webhook on the blaster or a home automation hub that can control it.

1. Put the emitter within sight of the HK 3770’s front-panel IR sensor. If yours is a stick-on emitter with a 3.5 mm plug, connect it to the emitter output of its controller and place the LED at the receiver’s front sensor. The controller supplies the signal. A USB IR transmitter similarly needs a host and sending software that supports its model.
2. In the controller’s app, select the HK 3770’s **Power On** command from its device library, or start IR learning, aim the original HK handset at the learner, and press **ON** once. Name the command `power_on`. The original handset has separate On and Off keys. [HK 3770 owner’s manual, remote controls](https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=9)
3. When you can see the stereo and it is in standby, send that saved command once from the controller’s app. Verify the receiver powers on. Sending the same command to an already-on receiver should leave it on.

### Connect the controller to Otoha

1. Configure your controller or home automation hub to send that one learned command when it receives an **HTTP POST**. Otoha sends an empty request body and expects a prompt HTTP 2xx response. Use a URL reachable on the controller’s home network. Controllers that require a vendor-specific payload or authentication headers need a small adapter or a hub automation.
2. Paste the full URL in **Power-on webhook URL** and choose **Link blaster**. Use HTTP or HTTPS and the controller’s private IPv4 address. The browser bridge also accepts a `.local` hostname that resolves to a private IPv4 address. Use the final endpoint directly. The iPhone app saves the URL in its Keychain and sends requests on the controller’s Wi-Fi. The browser saves its link separately on the bridge. Both show **Custom IR blaster**. Saving sends no power command.
3. With the receiver in standby, open **Power → Power on** and tap once. The success message confirms that the controller accepted the request. **Connected** appears when the receiver’s network service comes back. To replace the URL, choose **Infrared wake → Forget blaster**, then open **Not listed** again.

If the browser reports that the controller is already configured on the Mac, use **Configure Infrared Wake.command** on that Mac to update its webhook. An existing `OTOHA_IR_WAKE_URL` environment setting takes precedence.

### Optional Home Assistant webhook

In Home Assistant, add the BroadLink integration. Open **Developer tools → Actions** and select `remote.learn_command`. Choose your BroadLink remote entity and supply device `hk3770` and command `power_on`. When its LED blinks, point the HK handset at it and press **ON**. Test `remote.send_command` with the same entity, device and command. [BroadLink learning and sending actions](https://www.home-assistant.io/integrations/broadlink/)

Under **Settings → Automations & scenes**, create an automation with a **Webhook** trigger. Keep the generated secret ID, allow **POST**, and keep **local only** enabled. Set the action to the tested `remote.send_command` with one transmission. Save it. In **Not listed**, paste the resulting LAN URL, such as `http://192.168.1.20:8123/api/webhook/YOUR-GENERATED-ID`. [Home Assistant webhook trigger](https://www.home-assistant.io/triggers/webhook/)

If Otoha says the infrared request was accepted and the stereo stays asleep, test the controller’s learned command directly and check the emitter’s alignment. If the controller works on its own, check the webhook’s method and automation trace.
