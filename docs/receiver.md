# HK 3770 control protocol

## Evidence

Harman Remote for Android selects a dedicated HK 3700-series implementation when a discovered model name contains `3770`. This note follows that implementation from its buttons to the outgoing messages. The reference artifact is Harman International Industries’ `com.harman.hkremote` version 4.5, build 82, SHA-256 `5cd50ddca667fb1aea5d972fd71054bf5292bb2850a3036897e4b304b074f85c`. Its signing certificate names Harman Shenzhen and has SHA-1 fingerprint `C2:7A:9A:74:A1:DE:7C:C6:2C:B6:53:98:09:01:17:A7:BA:7C:9F:C3`. The wire values below come from inspecting that artifact. Firmware-specific responses require an observation from the receiver. [Harman Kardon product page](https://tw.harmankardon.com/HK%2B3770.html) · [Application build and certificate](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/) · [Build checksum](https://apkpure.net/harman-kardon-remote/com.harman.hkremote/download)

## Transport

The model-specific `CommandSetHK3700` sends a TCP frame on port 10025. Its first line is `POST avr HTTP/1.1`, with lowercase `avr`. The Android app uses the headers `Host: :10025`, `User-Agent: Harman Remote Controller/1.0`, and `Content-Length`, followed by a CRLF blank line and UTF-8 XML. For the model’s ASCII command set, the body’s UTF-8 byte count gives the content length. The upstream HKAPI’s generic AVR implementation supplies a different first line and user agent. [HK Remote 4.5](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/) · [HKAPI AVR implementation](https://github.com/KarimGeiger/HKAPI/blob/master/lib/Devices/AVR.php)

One press of Harman Volume sends this XML body.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<harman><avr><common><control>
  <name>harman_volume</name><zone>Main Zone</zone><para></para>
</control></common></avr></harman>
```

## Harman Volume and inputs

The receiver’s front-panel button and handset cycle **High, Low and Off**. The app’s HK 3700-series handler sends the `harman_volume` command, using `Main Zone` and an empty parameter. The related BDS receiver screen has its own mode dialog. The HK 3770 path sends one press and provides no absolute-mode setter or Harman Volume query. Without receiver readback, the front-panel display is the reference for the current mode. [Owner’s manual, pp. 6 and 9](https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=9) · [HK Remote 4.5](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/)

The `HK3700SourceView` buttons map through `CommandSet.initCommandHashMap` to `source-selection` with the following case-sensitive parameters. [HK Remote 4.5](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/)

| Source button | Parameter | Zone |
| --- | --- | --- |
| TV | `TV` | `Main Zone` |
| Bluetooth | `Bluetooth` | `Main Zone` |
| Phono | `Phono` | `Main Zone` |
| CD | `Disc` | `Main Zone` |
| Cable/Sat | `Cable Sat` | `Main Zone` |
| FM/AM | `FM` | `Main Zone` |
| Network | `Home Network` | `Main Zone` |
| Internet radio | `vTuner` | `Main Zone` |
| USB/iPod | `USB`, followed by `iPod` after 50 ms in the Android button handler | `Main Zone` |
| Digital | `Digital` | `Main Zone` |
| Analog | `Analog` | `Zone` |

The receiver associates physical analog/digital connections with a source selection. For example, the handset lets the owner assign analog input 1 to CD. The manufacturer’s source-selection table accordingly uses logical names such as `Disc`. [Owner’s manual, p. 9](https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=9)

## Feedback and power

The app’s `MessageHandlerHK3700` reads incoming XML at `harman/avr/common/status` and extracts `name`, `zone`, and `para`. A session uses `heart-alive` with **both** zone and parameter empty. The shared command table also defines `query-status` with a main zone and parameters including `volume`, `source`, `mute`, and `power`. The HK 3770 screen does not depend on these queries for its buttons. An emitted command or successful socket write alone cannot confirm a setting. [HK Remote 4.5](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/)

The HK 3700-series app’s power button sends `standby` with an empty parameter. Its sleep-timer button sends `Sleep` with a capital S. The shared table includes the discrete `power-on` command. Wake over that transport requires the receiver to keep its network control service running. The manual describes app power control and physical handset wake. A firsthand report for the related HK 3700 records immediate loss of Ethernet after `power-off`. With the network service unavailable, a home IR transmitter can send a learned discrete **On** press from the original handset. [Owner’s manual, pp. 9, 13 and 16](https://support.harmankardon.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dwc89ee311/pdfs/HK3700_3770_OM_EN.pdf#page=13) · [HKAPI owner observations](https://github.com/KarimGeiger/HKAPI/commit/6036d4f42b94f23cf62b1186ca95587f42e10e04#commitcomment-16323929) · [HK Remote 4.5](https://www.apkmirror.com/apk/harman-consumer-inc/harman-kardon-remote/harman-kardon-remote-4-5-release/harman-kardon-remote-4-5-android-apk-download/)

## Independent hardware observations

An HK 37xx integration tested the same TCP command path and a separate UPnP RenderingControl service. Its author reports that physical volume moves after an IR-over-IP volume command while the DLNA `GetVolume` value can stay fixed. Consequently, that value can describe the renderer even while the amplifier is playing another input at a different level. The integration remembers the last logical input selected and implements Harman Volume as a cycle button. [Tested receiver client](https://github.com/wongy123/harman-kardon-stereo-receiver/blob/cf38559ae2a9034518530d842e096b2ef5584f28/custom_components/hk37xx/client.py) · [Source tracking](https://github.com/wongy123/harman-kardon-stereo-receiver/blob/cf38559ae2a9034518530d842e096b2ef5584f28/custom_components/hk37xx/coordinator.py)

The same integration reports that its receiver closes the IR-over-IP port in standby and advertises `magicPacketWakeSupported=0`. Its Frontier Silicon SSDP service identifies IP tunneling. Neither the manufacturer's app nor this integration establishes a Frontier Silicon FSAPI endpoint for absolute Harman Volume or power-on. Harman's support guidance for an HK Remote device in full standby is to wake it with the handset or front panel. [HK 37xx observations](https://github.com/wongy123/harman-kardon-stereo-receiver/tree/cf38559ae2a9034518530d842e096b2ef5584f28#power--wake-on-lan-caveat) · [Harman remote support](https://support.harmankardon.com/us/en/howto/?dir=desc&sort=name&start=230&sz=12)

## Checks on the connected receiver

The target announced itself through SSDP as a Harman Kardon HK 3770 MediaRenderer. Its device description at `http://<receiver>:8080/dd.xml` advertised a RenderingControl service and reported `magicPacketWakeSupported` as `0`. Its tunnel description at `http://<receiver>:7070/devicedescription.xml` pointed to TCP port 10025. Both descriptions were read from the receiver during development.

A native `heart-alive` request produced a status frame on the same TCP connection. The unit occasionally closed that connection silently while its rendering service continued answering. The bridge therefore also recognizes connectivity when the TCP frame was written and the previously identified receiver returns valid renderer feedback. The same receiver did not answer the tested `query-status` requests for power, source, or volume. SOAP `GetVolume` and `GetMute` returned valid values. Its RenderingControl service description advertises volume from 0 through 100.

For amplifier volume, Otoha uses the relative volume commands from the handset. Another HK 3770 owner observed that these keys can change the audible amplifier level while the DLNA register retains its earlier value. The absolute DLNA slider lives in Receiver settings. [HK 3770 implementation and hardware observations](https://github.com/wongy123/harman-kardon-stereo-receiver/blob/cf38559ae2a9034518530d842e096b2ef5584f28/custom_components/hk37xx/client.py)
