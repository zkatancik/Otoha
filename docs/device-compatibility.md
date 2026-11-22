# Harman Kardon network remote compatibility

Research checked November 22, 2026. The best-documented market includes the HK 3700/3770 stereo receivers, 18 AVR model designations, ten BDS receiver designations sold in multiple speaker packages, and the Wi-Fi editions of Aura and Onyx. They share a family of XML commands on TCP 10025. The request target, XML element and usable controls depend on the product. Harman published an app compatibility list. Public hardware evidence covers a subset, and firmware and regional bundles leave the worldwide inventory open. [Harman’s Android listing][play] · [Harman’s iOS listing and version history][apple] · [HKAPI tested devices][hkapi] · [Signed Android application][app]

## Products and evidence

“App” means Harman identified the product and the signed Android application contains the corresponding protocol implementation. “Hardware” means an owner, integration author or this project observed traffic or exercised controls on a named unit. Hardware reports cover the commands each source tested. The project’s own physical observations are for the HK 3770. [HK 3770 observations](receiver.md#checks-on-the-connected-receiver)

| Product family | Product designations | Evidence for network control |
| --- | --- | --- |
| HK stereo | **HK 3700, HK 3770** | Harman documents both. HKAPI owners report HK 3700 control. Otoha observed the HK 3770 heartbeat and UPnP services. [Stereo manual][stereo] · [HKAPI][hkapi] · [Otoha observations](receiver.md) |
| AVR x70 | **AVR 170, 1700, 270, 2700, 370, 3700** | App covers all six. Hardware reports cover 170 and 370 in HKAPI and a published AVR 270 source-selection capture. AVR 170 can accept controls without answering a heartbeat. [App][apple] · [HKAPI][hkapi] · [AVR 270 owner capture][avr270] |
| AVR x1 | **AVR 151, 1510, 161, 1610, 171, 1710** | App covers all six. An AVR 151 owner captured the volume command on TCP 10025. HKAPI reports AVR 1510. [App][apple] · [AVR 151 capture][avr151] · [HKAPI][hkapi] |
| AVR x1 S | **AVR 151S, 1510S, 161S, 1610S, 171S, 1710S** | App covers all six. Home Assistant names the 151S. HKAPI reports the 161S. A client author identifies their test unit by the combined label “171S/1710S”. [App][apple] · [Home Assistant][ha] · [HKAPI][hkapi] · [171S client][avr171s] |
| BDS x75/x77 | **BDS 275, 277, 575, 577** | Harman lists all four receivers. HKAPI reports 277 and systems sold as 375 and 7773W. A BDS 577 owner captured its G3 discovery announcement. [Receiver manual][g3manual] · [App][play] · [HKAPI][hkapi] · [BDS 577 capture][g3] |
| BDS x80/x80S | **BDS 280, 580, 280S, 580S** | Harman identifies both generations. The app matches the 280/580 family and checks the firmware’s `/80s` marker. One owner reports intermittent remote connectivity on a BDS 580. [App history][apple] · [x80 systems][x80] · [x80S manual][x80s] · [Owner observations][bds580] |
| BDS x35 | **BDS 235, 535** | App identifies both receiver names. Harman sells them in the **335** and **635** systems respectively. [App][app] · [335 box contents][bds335] · [635 box contents][bds635] |
| Wi-Fi speakers | **Aura, Aura Plus, Onyx** (original Wi-Fi Onyx) | App routes Aura and Onyx to separate screens using the same `MM` command envelope. An Aura owner captured SSDP. An Aura Plus owner published its description, controls and power behavior. [Aura manual][aura] · [Onyx manual][onyx] · [Aura Plus capture][auraplus] · [Aura owner capture][aurassdp] |
| Related JBL hardware | **JBL AVR 101** | A Home Assistant integration author exercised the AVR commands on this JBL unit. This is evidence for one cross-brand receiver. Further JBL models would need independent identification. [Owner’s test and frame][jbl] |

**Regional labels.** Harman’s app displays paired names such as `AVR 171/1710` and `AVR 171S/1710S`. Harman’s manuals also document `/230` and `/230C` labels on 151, 161 and 171, and `/230C` on 170, 151S, 161S and 171S. Preserve the reported label when the individual regional model is ambiguous. An **AVR 3700** is a surround receiver with an AVR profile. An **HK 3700** is a stereo receiver with a different profile. [Android app][app] · [AVR x1 regional guide][regional] · [AVR 170 manual][170manual] · [151S manual][151smanual] · [161S/171S manual][161smanual]

**BDS package names.** Buyers may know only the number on the original box. The device to link is the receiver inside the package.

| Receiver generation | Retail system names | Source |
| --- | --- | --- |
| 275/277/575/577 | 375, 477, 775, 877, 7773W | [Harman’s launch announcement][g3kits] · [HKAPI field reports][hkapi] |
| 280/580 | 380 and 480 use the 280. The 680, 780 and 880 use the 580. Color variants include 480W and 780W. | [Harman’s system lineup][x80] · [Harman regional lineup][x80colors] · [Harman regional price list][prices] |
| 280S/580S | 385S, 485S, 685S, 785S, 885S | [Harman’s package manual][x80s] |
| 235/535 | 335 contains the 235. The 635 contains the 535. | [335 specifications][bds335] · [635 specifications][bds635] |

Harman also advertised a companion app for the **BDS 3772 and 7772** packages. Their spec sheets do not identify a control frame or head-unit model. Use the discovered receiver identity to establish compatibility. [3772 specifications][3772] · [7772 specifications][7772]

## What the network can establish

For standby settings, firmware differences and Otoha’s infrared setup policy, see [power-on behavior by model](standby-wake.md).

The references below come from inspection of Harman’s `com.harman.hkremote` 4.5, build 82, SHA-256 `5cd50ddca667fb1aea5d972fd71054bf5292bb2850a3036897e4b304b074f85c`. The relevant code is in `device.net.UdpClientHelper`, `DeviceWifiManager.onDeviceFound`, `parserMsgDevice`, and the model-specific `CommandSet` classes. HKAPI’s PHP source independently records the AVR and legacy BDS framing. [Signed application][app] · [HKAPI AVR class][avrwire] · [HKAPI BDS class][bdswire]

| Profile | Request target | XML under `harman` | What identifies it |
| --- | --- | --- | --- |
| HK stereo | `POST avr` | `avr` | HK 3700/3770 model. Otoha’s 3770 advertises `:8080/dd.xml` and a separate Frontier Silicon tunnel description on 7070. [Otoha observations](receiver.md) |
| AVR | `POST AVR` | `avr` | AVR model/region in the device description. The vendor app handles all nine slash-paired AVR names. [App][app] · [AVR capture][avr270] |
| BDS G3 | `POST HK_APP` | `bds` | An observed BDS 577 advertises the vendor remote service with server text `Harman Kardon BDS G3` and a location ending in `:10025/remote-controller`. The advertisement may identify only the generation. [BDS capture][g3] · [HKAPI BDS][bdswire] |
| Later BDS | `POST BDS` | `bds` | The app dispatches Harman Kardon BDS 280/580 and 235/535 names to `CommandSetBDS`, distinct from G3’s `CommandSetBds3`. [App][app] |
| Aura/Onyx | `POST MM` | `mm` | The app recognizes forms of `HK Aura`, `HK Onyx` and the internal `soundtube` identifier. The published Aura Plus description has manufacturer `Harman Kardon`, model name `HK Aura` with trailing whitespace, and a friendly name beginning `HK Aura WF`. The description alone can leave the Plus edition ambiguous. [App][app] · [Captured descriptor][auradd] |

All five frames use TCP 10025, an HTTP/1.1-style request line, `Content-Length`, a CRLF header separator and an XML `common/control` element containing `name`, `zone` and `para`. For these ASCII controls the body’s UTF-8 byte count is the correct length. The signed app sends `Harman Remote Controller/1.0` for stereo, later BDS and MM, `Harman Kardon BDS Remote Controller/1.0` for G3, and an AVR-specific controller user agent for AVR. [App][app] · [HKAPI transport][transport] · [AVR capture][avr270]

**Locate.** The stock app multicasts SSDP M-SEARCH to `239.255.255.250:1900`. Its search targets include `upnp:rootdevice`, `upnp:all` and the literal `harman-com:service:remote-controller:1` for BDS G3. A later BDS probe also uses quoted `"upnp:rootdevice"`. On descriptor-based products it reads `modelName` and falls back to `friendlyName` if the former is empty or `none`. An Aura’s observed description URL is `:8080/description.xml`. The G3 remote-service location points directly to a control service. Showing the advertised identity and address gives the owner a way to distinguish two receivers in the same house. [App][app] · [BDS G3 advertisement][g3] · [Aura discovery capture][aurassdp]

**Identify G3 announcements.** The BDS 577 capture includes `NTS: ssdp:alive`, the vendor service under `NT`, and a bare `USN` beginning with `uuid:`. Its identifier has four hyphen-separated groups of 8, 4, 4 and 16 hex digits. A strict RFC UUID parser would discard this receiver. The request target for sending commands remains `HK_APP`. [Owner’s discovery capture][g3] · [Owner’s heartbeat capture][g3frames]

**Link.** The app’s read-only `heart-alive` uses empty zone and parameter fields. Replies vary by profile.

- A BDS 577 returns another `POST HK_APP HTTP/1.1` frame on the connection, containing `harman/bds/common/status` with name `heart-alive` and empty zone and parameter. Multiple frames can arrive back-to-back. [Owner’s heartbeat capture][g3frames]
- Harman’s AVR handler reads `harman/avr/common/control` and recognizes heartbeat replies tagged `Main Zone` or `Zone 2`. The AVR 151 owner capture confirms volume on TCP 10025 and DLNA on 8080. It supplies no heartbeat trace or exact model descriptor. The AVR 170 has a documented silent-heartbeat exception. [App][app] · [AVR 151 capture][avr151] · [HKAPI field notes][hkapi]
- Onyx and Aura’s Android receive paths look for an XML declaration and the `name`, `zone` and `para` fields. The Aura Plus hardware client also accepts a standard HTTP POST to `/` with an `mm` body and documents timeouts on some writes. The cited Aura captures provide no exact heartbeat response envelope. [App][app] · [Aura Plus control client][auraclient] · [Captured request template][auratemplate]
- HK 3770 can reply with a status heartbeat, or close a command socket while its renderer still serves readbacks. A read-only identity match combined with TCP reachability gives weaker evidence than a recognized command reply. An arbitrary open port or a generic DLNA renderer supplies insufficient evidence of amplifier control. [Otoha observations](receiver.md#checks-on-the-connected-receiver)

**Choose controls by profile.** HK stereo and AVR support relative amplifier volume commands. Harman’s MM screens send absolute `set_system_volume`, discrete `power-off` and, on Onyx, `mute-on`/`mute-off`. The Aura Plus owner independently exercised those discrete mute actions and absolute volume 0–100. Within the HK stereo pair, the manual reserves Harman Volume cycling, Bluetooth and digital audio inputs for the **HK 3770**. Renderer volume can differ from amplifier volume on this unit. [App][app] · [Aura Plus control client][auraclient] · [Stereo manual, pp. 6–9][stereocontrols] · [HK 3770 controls and readback](receiver.md)

**Standby and setup.** Put the product on the same home network as the iPhone and power it on before discovery. Some models need wired Ethernet. Full standby can take the IP service offline, including on reported HK 3700, AVR and Aura Plus units. A physical power-on or model-specific wake method can be necessary before discovery succeeds again. [Harman network setup][play] · [Home Assistant standby notes][ha] · [HKAPI][hkapi] · [Aura Plus owner’s wake observations][aurassdp]

## Products that need a different integration

Harman’s legacy app also lists **SB26, Sabre SB35 and Go + Play Wireless**. Their documented app paths use Bluetooth. The publisher’s brand-wide app listing therefore covers products beyond the TCP remote. Harman’s Omni platform has its own REST/JSON interface. Aura Studio and Studio 2 use Bluetooth, and similarity to the Wi-Fi Aura or Onyx names is insufficient evidence for any Studio generation. No TCP 10025 support claim is established here for Citation, Enchant, later Studio speakers or arbitrary network-enabled receivers. [Harman app listing][apple] · [SB26 manual][sb26] · [SB35 manual][sb35] · [Go + Play support][goplay] · [Omni developer specification][omni] · [Aura Studio support][studio]

[play]: https://play.google.com/store/apps/details?id=com.harman.hkremote
[apple]: https://apps.apple.com/us/app/harman-kardon-remote/id549776020
[app]: https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/
[hkapi]: https://github.com/KarimGeiger/HKAPI#tested-devices
[stereo]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw0b717540/pdfs/HK3700_3770_OM_EN-1.pdf#page=16
[stereocontrols]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw0b717540/pdfs/HK3700_3770_OM_EN-1.pdf#page=9
[avr270]: https://forum.fhem.de/index.php?topic=35469.0
[avr151]: https://things.adamparsons.id.au/hk-avr-151-remote-control-api/
[ha]: https://www.home-assistant.io/integrations/harman_kardon_avr/
[avr171s]: https://github.com/dannyvanlierop/NodeJS_API_HarmanKardon_AVR
[g3manual]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwada0bbc6/pdfs/BDS_X75_X77_OM_EN.pdf
[g3]: https://homematic-forum.de/forum/viewtopic.php?t=18971
[g3frames]: https://homematic-forum.de/forum/viewtopic.php?t=18971&start=10
[bds580]: https://wiert.me/2022/05/03/remotely-controlling-most-harman-kardon-systems/
[x80]: https://news.harman.com/releases/ifa-2013%3A-harman-kardonR-fuses-iconic-design-and-innovative-performance-to-create-objects-of-desire
[x80colors]: https://www.mynewsdesk.com/se/harman/pressreleases/ifa-2013-harman-kardon-r-vaecker-habegaer-genom-att-blanda-ikonisk-design-med-innovativ-prestanda-902139
[prices]: https://www.cieri.net/Documenti/Harman-Kardon/Cataloghi/Harman-Kardon%20-%20Listino%20prezzi%20Home%20Hi-Fi%20%282015-07%29.pdf
[x80s]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwb2fcfd40/pdfs/Owners%20Manual%20-%20BDS%20x85S%20%28English%29-1.pdf
[bds335]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwd0543651/pdfs/TR01252%20HK%20BDS%20335%20Home%20Theater%20System%20EN%20Spec%20Sheet%20Final%2013%20Dec.pdf
[bds635]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw7baf5b59/pdfs/Specification%20Sheet%20-%20HK%20BDS%20635%20%28English%29.pdf
[aura]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw24f06801/pdfs/Owners%20Manual%20HK%20Aura%20%28English%29.pdf
[onyx]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwa6cd77a0/pdfs/ONYX_OM_EN.pdf
[auraplus]: https://github.com/vakintosh/hk_aura_protocol_analysis
[auradd]: https://github.com/vakintosh/hk_aura_protocol_analysis/blob/main/xml_files/description.xml
[auraclient]: https://github.com/vakintosh/hk_aura_protocol_analysis/blob/main/Harman_Kardon_Remote/hk_app.py
[auratemplate]: https://github.com/vakintosh/hk_aura_protocol_analysis/blob/main/Harman_Kardon_Remote/hk_request_template.xml
[aurassdp]: https://community.home-assistant.io/t/harman-kardon-aura-speaker-control/186668
[jbl]: https://community.home-assistant.io/t/harmon-kardon-avr/7567/8
[regional]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwa4e080eb/pdfs/AVR%201510_QSG_EN.pdf
[170manual]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw8976f1e5/pdfs/Owners%20manual%20-%20AVR170%20%28English%29.pdf
[151smanual]: https://www.harmanaudio.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwb7f45fca/pdfs/AVR1510S_OM_EN.pdf
[161smanual]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw2c314d7a/pdfs/Owner%27s%20Manual%20-%20AVR%20161S%20and%20171S.pdf
[g3kits]: https://www.mynewsdesk.com/dk/harman/pressreleases/harman-kardon-praesenterer-et-udvalg-af-nye-produkter-til-hjemmeunderholdning-803815
[3772]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc87dc582/pdfs/BDS3772_SS_EN.pdf
[7772]: https://support.harmanaudio.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw9c6d99ef/pdfs/BDS7772_SS_EN.pdf
[avrwire]: https://github.com/KarimGeiger/HKAPI/blob/master/lib/Devices/AVR.php
[bdswire]: https://github.com/KarimGeiger/HKAPI/blob/master/lib/Devices/BDS.php
[transport]: https://github.com/KarimGeiger/HKAPI/blob/master/lib/API.php
[sb26]: https://www.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw5f8eef31/pdfs/SB26_OM_EN.pdf
[sb35]: https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw1131015a/pdfs/Owners%20Manual%20SB35%20SABRE.pdf
[goplay]: https://support.harmankardon.com/sg/en/howto/?dir=desc&sort=viewcount&start=100&sz=60
[omni]: https://hkwirelesshdapi.readthedocs.io/en/latest/restapi-specification.html
[studio]: https://support.harmankardon.com/us/en/howto/?Puhf5JAJ=NZd5Z0Q&dir=desc&sort=viewcount&start=139&sz=24
