# Power-on behavior by Harman Kardon model

Harman documents several ways to wake these products, including the original handset, a phone app, Bluetooth audio, AirPlay and DLNA playback. **Standby mode and firmware determine which wake methods are available. An always-on HK remote API (TCP port 10025) remains unverified across all standby states for every model reviewed.** The table covers all 73 model and alias keys in Otoha’s catalog as of November 22, 2026. This was a source review, with earlier hardware observations identified below. [Otoha model catalog](../ios/Otoha/receiver-profiles.json) · [Otoha protocol evidence](device-compatibility.md)

## Stereo receivers

| Model | Power-on evidence | Infrared setup in Otoha |
| --- | --- | --- |
| **HK 3700** | Harman describes app power-on while the receiver is on the network. An owner using the HK command protocol observed Ethernet drop immediately after sending Off. The original handset or front-panel button wakes the unit from standby. [Manual, pp. 9, 13, 16][stereo] · [HK 3700 owner’s test][3700-test] | Optional after connection. The HK 3770 service parts list identifies the shared HK 37xx handset as CARTHK3700. Otoha uses the HK 3770 discrete On preset on that basis. [Service manual][3700-handset] |
| **HK 3770** | The same manual describes app power-on. An HK 37xx integration author reports port 10025 closes in standby. Otoha’s own awake HK 3770 reported no Wake-on-LAN magic-packet support. That flag alone cannot establish what the control port does in standby. [Manual, pp. 9, 13, 16][stereo] · [Integration author’s observations][3770-test] · [Otoha hardware notes][hardware] | Optional after connection. Otoha uses the discrete On preset for the shared HK 37xx handset. [IR setup](infrared-wake.md) |

Harman’s EU service manual also lists Bluetooth audio as a way to wake the HK 3770 from standby. The consumer manual lists the power and source buttons. Bluetooth audio would be a separate wake path from Otoha’s Wi-Fi power button, and this review did not test that behavior on a receiver. [HK 3770 service manual, p. 4](https://device.report/m/00d7e4bfff65b53b891034092c9a7951c8c9d35b4145cc02d5d88245e44bb71f.pdf#page=4) · [Owner’s manual, pp. 5, 13][stereo]

## AV receivers

Otoha offers optional blaster setup after connecting an AVR 170/1700, 370/3700 or 151S/1510S, including their catalogued aliases. These families have reported standby disconnections and handset On buttons. The receiver’s original handset teaches a BroadLink RM the command for that unit. The offer is hidden on other AVRs where the evidence for loss of Wi-Fi remote power-on is inconclusive. [AVR 170 handset][170] · [AVR 370 handset][270] · [AVR 151S handset][151s-handset] When a manual describes the Harman Remote app turning on a network-connected AVR, it does not identify which power states continue accepting that command. Starting audio playback is a separate operation that can switch the source.

| Models | Documented wake behavior |
| --- | --- |
| **AVR 170, 1700** | Starting AirPlay can wake ordinary Standby. Eco Standby blocks AirPlay wake. On one AVR 170, firmware 2.0 kept the network available. On 3.0 the owner could still send network commands in Sleep, but after another 20 minutes the unit entered Off. The front panel or handset can wake either standby mode. [Manual, p. 5][170] · [AVR 170 firmware comparison][170-test] |
| **AVR 270, 2700, 370, 3700** | AirPlay can wake ordinary Standby. Eco Standby blocks it. Harman also documents app on/off for a network-connected unit. The HKAPI author observed their AVR 370 disconnect after a few minutes. The rear power switch must be on. [Manual, pp. 5, 29][270] · [AVR 370 developer’s observation][370-test] |
| **AVR 151, 1510** | A DLNA Digital Media Renderer stream can wake Sleep. Off disables network streaming wake. The Auto Power Off setting can move the unit from Sleep into Off. Harman documents app on/off while connected. [Manual, pp. 5, 23][151] |
| **AVR 151S, 1510S** | Same documented Sleep/Off distinction and app on/off. On an AVR 151S, a network integration also reports losing remote power-on after the firmware’s automatic shutdown. [Manual, pp. 5, 23][151s] · [Integration observations][151s-test] |
| **AVR 161, 1610, 161S, 1610S** | The manuals document Sleep, timed or manual Off, and app on/off while connected. Their explicit streaming-wake instructions name the 171-series models. The 161-series standby TCP wake remains unverified. [161/171 manual, pp. 5, 25][161] · [S manual, pp. 5, 25][161s] |
| **AVR 171, 1710, 171S, 1710S** | AirPlay or DLNA playback can wake Sleep. Off disables AirPlay wake. The manuals also document app on/off while connected. [161/171 manual, pp. 5, 25][161] · [S manual, pp. 5, 25][161s] |

Otoha also recognizes the paired labels 151/1510, 151S/1510S, 161/1610, 161S/1610S, 171/1710, 171S/1710S, 170/1700, 270/2700 and 370/3700. Regional labels include 151/230, 161/230, 171/230, 151/230C, 161/230C, 171/230C, 170/230C, 151S/230C, 161S/230C and 171S/230C. Each maps to the corresponding AVR row. Regional and firmware variants were not individually bench-tested. [Regional model references](device-compatibility.md#products-and-evidence)

## BDS home theater systems

The original remote can wake these systems from full Standby with AC connected and the rear switch on. With the rear switch off, supplying an IR signal does not restore power. The documented wireless wake paths below apply to Sleep. Otoha keeps its IR setup hidden across these families. [x75/x77 manual, pp. 5, 8, 16][bds75] · [x80 manual, pp. 5–8][bds80] · [x80S manual, pp. 5–8][bds80s] · [335/635 manual, pp. 6–8][bds35]

| Receiver or retail system label | Documented wake behavior |
| --- | --- |
| **BDS 275, 575** and systems **375, 775** | Bluetooth audio wakes Sleep. With Auto Standby configured for Sleep, the receiver can enter full Standby after 15 minutes in Sleep. [Manual, pp. 8, 16][bds75] · [Harman’s package lineup][bds-kits] |
| **BDS 277, 577** and systems **477, 877, 7773W** | AirPlay or Bluetooth audio wakes Sleep. The corresponding transition to full Standby is after 30 minutes in Sleep. Full Standby blocks those audio wake paths. [Manual, pp. 8, 16][bds75] · [Harman’s package lineup][bds-kits] |
| **BDS G3** without a model number | This discovery label covers the two preceding groups. It does not identify which model or standby mode the customer has. [G3 identification](device-compatibility.md#what-the-network-can-establish) |
| **BDS 280, 580** and systems **380, 480, 480W, 680, 780, 780W, 880** | Sleep supports Bluetooth or AirPlay wake. A long power-button press selects deeper Standby. The manual also documents wake by tapping compatible NFC hardware. [Owner’s manual, pp. 5–8][bds80] · [Package mapping](device-compatibility.md#products-and-evidence) |
| **BDS 280S, 580S** and systems **385S, 485S, 685S, 785S, 885S** | Sleep supports Bluetooth or AirPlay wake. Full Standby uses different wake controls. [Owner’s manual, pp. 5–8][bds80s] |
| **BDS 235, 535** in systems **335, 635** | The manual lists Bluetooth wake in Sleep and handset Power in full Standby. [Owner’s manual, pp. 6–8][bds35] |

## Wi-Fi speakers

| Model | Power-on evidence |
| --- | --- |
| **Aura** (including **SOUNDTUBE**) and **Aura Plus** | Harman documents Bluetooth signal wake in Sleep and Standby. The speaker can stay in Sleep on Wi-Fi and proceed to Standby after inactivity without Wi-Fi or a manual power-off. An Aura owner reports that Bluetooth audio restores the TCP service after Wi-Fi power-off. Otoha exposes no IR setup or speaker Power On command. [Aura support][aura] · [Aura Plus support][aura-plus] · [Aura Plus manual, pp. 6–7][aura-manual] · [Owner’s test][aura-test] |
| **Onyx**, original Wi-Fi model | Harman identifies operational, Sleep and Off states and documents a long press of the speaker’s power button to wake from Off. Its AirPlay and DLNA playback support does not establish wake from Off. Otoha exposes no IR setup or speaker Power On command. [Owner’s manual, pp. 3, 7][onyx] · [Otoha speaker command profile](../ios/Otoha/receiver-profiles.json) |

## Verifying another unit

Link and identify the receiver while it is on. With the iPhone on the same Wi-Fi, place the receiver into the specific state being tested. Record the front-panel indication, standby settings, firmware and elapsed time. Attempt Wi-Fi Power On and observe whether the receiver actually turns on. Repeat after any automatic transition to deeper standby. If Wi-Fi fails but the original handset wakes the unit, record that result separately. A missed discovery packet, an outage, an open port or a successful write by itself does not establish a power transition. [Protocol and readback limits](receiver.md#feedback-and-power)

[stereo]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=16
[3700-handset]: https://device.report/m/00d7e4bfff65b53b891034092c9a7951c8c9d35b4145cc02d5d88245e44bb71f.pdf
[151s-handset]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwd8b8cb4d/pdfs/AVR1510S_OM_EN.pdf#page=9
[3700-test]: https://github.com/KarimGeiger/HKAPI/commit/6036d4f42b94f23cf62b1186ca95587f42e10e04#commitcomment-16323929
[3770-test]: https://github.com/wongy123/harman-kardon-stereo-receiver/blob/cf38559ae2a9034518530d842e096b2ef5584f28/README.md#power--wake-on-lan-caveat
[hardware]: receiver.md#checks-on-the-connected-receiver
[170]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dweede3744/pdfs/AVR1700_OM_EN-1.pdf#page=5
[270]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw53485fbe/pdfs/AVR270_370_2700_3700_OM_EN-1.pdf#page=5
[151]: https://www.harmanaudio.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw89859d41/pdfs/Owners%20Manual%20-%20AVR%20151-1510%20-151230C%20%28English%29.pdf#page=5
[151s]: https://www.harmanaudio.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwb7f45fca/pdfs/AVR1510S_OM_EN.pdf#page=5
[170-test]: https://github.com/KarimGeiger/HKAPI/commit/6036d4f42b94f23cf62b1186ca95587f42e10e04#commitcomment-16555062
[370-test]: https://github.com/KarimGeiger/HKAPI/commit/6036d4f42b94f23cf62b1186ca95587f42e10e04#commitcomment-16323993
[151s-test]: https://www.home-assistant.io/integrations/harman_kardon_avr/
[161]: https://www.harmanaudio.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw08c6a261/pdfs/Owners%20Manual%20-%20AVR%201710-171-171-230C-1610-161-161-230C%20%28English%29.pdf#page=5
[161s]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw9e74157a/pdfs/AVR1610S_1710S_OM_EN-min.pdf#page=5
[bds75]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw3efa0329/pdfs/BDS_X75_X77_OM_EN.pdf#page=16
[bds-kits]: https://www.mynewsdesk.com/dk/harman/pressreleases/harman-kardon-praesenterer-et-udvalg-af-nye-produkter-til-hjemmeunderholdning-803815
[bds80]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwa1164f7b/pdfs/Owners%20Manual%20-%20BDS%20280%20580%20%28English%29.pdf#page=8
[bds80s]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwb2fcfd40/pdfs/Owners%20Manual%20-%20BDS%20x85S%20%28English%29-1.pdf#page=8
[bds35]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwf3a96034/pdfs/HK%20BDS%20335_635_OM_ENG_B_v4.pdf#page=8
[aura]: https://support.harmankardon.com/us/en/howto/the-device-does-not-go-into-standby-automatically-aura-us/000024037.html
[aura-plus]: https://support.harmankardon.com/ph/en/howto/does-a-bluetooth-signal-wake-the-unit-up-aura-apac/000024024.html
[aura-manual]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw53077a52/pdfs/TR02424_HK_Aura%20Plus_Owners%20Manual.pdf#page=7
[aura-test]: https://community.home-assistant.io/t/harman-kardon-aura-speaker-control/186668
[onyx]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwa6cd77a0/pdfs/ONYX_OM_EN.pdf#page=7
