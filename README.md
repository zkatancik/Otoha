# Otoha

Otoha turns your iPhone into a Wi-Fi remote for a compatible Harman Kardon receiver or speaker. [Check your stereo model](docs/device-compatibility.md).

## Get connected

1. Turn on your stereo and connect it to your home router. Use a network cable if the stereo requires one. Join the same home Wi-Fi on your iPhone.
2. Open Otoha. On **Select a device**, allow local network access, then tap your stereo’s name.
3. Tap **Connect**. Otoha checks that the selected device answers. On models that can lose their network connection in standby, Otoha offers an optional IR blaster for power-on. Choose **Connect an IR blaster** or **Not now**.
4. Choose the controls you want on your remote, or tap **Use defaults**.

Otoha remembers your stereo. To switch, open **Settings → Search for devices**, select a device, and tap **Connect**. If it’s missing, check that it’s on, join the same home Wi-Fi, and allow Otoha under **Settings → Privacy & Security → Local Network** on your iPhone.

## Optional infrared wake

An IR blaster, such as a BroadLink RM mini 3, sends the same infrared signal as your handheld remote. It lets the phone wake a receiver that has dropped off the home network in standby. If Wi-Fi power-on already works for you, choose **Not now**. You can add a blaster later under **Power → Infrared wake** on eligible models. [Blaster instructions](docs/infrared-wake.md) · [Standby behavior by model](docs/standby-wake.md)

## Personalize your remote

On iPhone, choose whole modules after linking a device. **Volume** includes the fader and mute, **Power** includes wake and standby, and **Inputs** lets you pin individual sources. **Use defaults** starts with the recommended layout. Saving opens the remote. On later launches, Otoha opens the saved remote for that device directly, including while the iPhone reconnects.

A chevron at the bottom points to more controls. Swipe down across the remote to open a narrow “Pull for more options” margin. Keep pulling to reveal the next page, or let a short pull settle back. Swipe up to return. The volume thumb keeps its own drag gesture. Tap a chevron or activate it with VoiceOver to turn one page. Change your selection under **Settings → Customize remote**. Earlier saved shortcut selections migrate to the corresponding modules.

## Listening controls

The following controls describe the HK 3770. Other models use their own source list and supported controls. Wi-Fi Aura and Onyx offer a requested absolute speaker level, discrete mute and unmute, and standby.

- **Master volume** sends the amplifier’s native volume keys. Drag the spring-loaded thumb up for louder or down for quieter. Tap the upper half (+) or lower half (−) for exactly one step. Hold it farther from center for faster repeats. Return to center or lift to stop. VoiceOver users can swipe up or down for one step. Mute sends the handset’s toggle.
- **Harman Volume** cycles High, Low, and Off. When you can see the front display, use **Sync** to record its current mode. You can then select a named mode from this iPhone. Otoha tracks the presses it sends. Sync again after using another remote. A disconnect, standby command, interrupted mode sequence, or app restart clears the estimate.
- **Phono and TV** are the quick inputs. The **More inputs** button beside them opens the remaining inputs, including CD, Bluetooth, radio, USB/iPod and network sources. “Last requested” identifies a command sent through Otoha. The receiver has no confirmed source readback.
- **Power** offers network wake, standby, and the receiver’s sleep timer. A closed network control port prevents an IP wake. A BroadLink RM mini can wake the receiver from standby with its discrete infrared On command.

## Build and distribution

The iOS target requires iOS 17 or later and builds with Xcode 27.1 or newer. For a computer-free installation, distribute the signed iPhone app through TestFlight or the App Store. This source checkout does not provide a public install link.

The standard build uses local, individually addressed SSDP discovery requests and BroadLink discovery on home networks of up to 1,022 hosts per subnet. Local Network permission is sufficient. Each receiver must identify itself and answer its control connection before the phone saves it. Each phone keeps its own linked stereo and settings.

For larger networks, receivers that only send multicast announcements, and Global Caché iTach discovery, build with `-xcconfig ios/Multicast.xcconfig`. This enables multicast SSDP, BroadLink broadcast discovery, and iTach beacons. Apple must grant the signing team Multicast Networking for that configuration. [Apple’s local networking requirements](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

See [receiver protocol notes](docs/receiver.md) for handset framing and known device behavior.
