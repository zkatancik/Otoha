# Otoha

Otoha is a React Native remote for Harman Kardon network receivers. The app talks
to the receiver using the same reverse-engineered TCP/XML protocol used by the
HK Remote app and the upstream PHP `HKAPI` project.

## Harman Kardon API

The active implementation lives in `lib/hkapi`. The local `HKAPI` directory is
the upstream PHP reference implementation; the app does not call PHP at runtime.

The receiver is controlled with an HTTP-like payload over TCP, usually on port
`10025`. AVR devices use the `POST AVR HTTP/1.1` header and BDS devices use
`POST HK_APP HTTP/1.1`. The XML body has one command name, one zone, and an
optional parameter:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<harman>
    <avr>
        <common>
            <control>
                <name>volume-up</name>
                <zone>Main Zone</zone>
                <para></para>
            </control>
        </common>
    </avr>
</harman>
```

Most commands are fire-and-forget: the receiver usually does not return state or
an acknowledgement. `heartAlive` is the only currently modeled command that reads
a response.

## Device Types And Zones

| Device type | Template | Default zones | Header |
| --- | --- | --- | --- |
| `avr` | `<harman><avr>...` | `Main Zone`, `Zone 2` | `POST AVR HTTP/1.1` |
| `bds` | `<harman><bds>...` | `Main Zone` | `POST HK_APP HTTP/1.1` |

`avr` is the default device type. Source names and zones must match what the
receiver expects; unsupported zones or source labels generally fail silently.

## Supported Actions

Actions are called by friendly JavaScript keys through `runStereoAction(action,
param)` or directly through `HKClient.zone(zoneName)`.

| Action key | Wire command | Param | Response | Notes |
| --- | --- | --- | --- | --- |
| `on` | `power-on` | none | no | Works only if the receiver's network service is reachable. |
| `off` | `power-off` | none | no | Some devices close the network service after this. |
| `sleep` | `sleep` | none | no | Often safer than `off` if you want later network control. |
| `volumeUp` | `volume-up` | none | no | One volume step per command. |
| `volumeDown` | `volume-down` | none | no | One volume step per command. |
| `muteToggle` | `mute-toggle` | none | no | Toggle only; no known state response. |
| `selectSource` | `source-selection` | source label | no | Source label must match the receiver menu. |
| `play` | `play` | none | no | Media transport command. |
| `pause` | `pause` | none | no | Media transport command. |
| `next` | `next` | none | no | Media transport command. |
| `previous` | `previous` | none | no | Media transport command. |
| `forward` | `forward` | none | no | Media transport command. |
| `reverse` | `reverse` | none | no | Media transport command. |
| `up` | `up` | none | no | Menu/navigation command. |
| `down` | `down` | none | no | Menu/navigation command. |
| `left` | `left` | none | no | Menu/navigation command. |
| `right` | `right` | none | no | Menu/navigation command. |
| `ok` | `ok` | none | no | Menu/navigation command. |
| `back` | `back` | none | no | Menu/navigation command. |
| `home` | `home` | none | no | Menu/navigation command. |
| `info` | `info` | none | no | Opens the receiver info menu when supported. |
| `options` | `options` | none | no | Opens the receiver options menu when supported. |
| `heartAlive` | `heart-alive` | none | yes | Diagnostic/keep-alive candidate; unsupported on some models. |

Example:

```js
await runStereoAction('volumeUp');
await runStereoAction('selectSource', 'Disc');
```

Or with the lower-level client:

```js
const zone = client.zone('Main Zone');
await zone.on();
await zone.selectSource('Radio');
```

## Source Parameters

`selectSource` takes the receiver's exact on-screen source label as its parameter.
Known labels from HKAPI and related wrappers include:

- `Cable Sat`
- `Disc`
- `DVR`
- `Radio`
- `TV`
- `USB`
- `Game`
- `Media Server`
- `Home Network`
- `AUX`
- `Source A`
- `Source B`
- `Source C`
- `Source D`
- `STB`
- `AM`
- `FM`
- `vTuner`
- `Bluetooth`
- `Spotify`
- `Phono`

Not every model supports every source. The app should allow custom source labels
because receiver menus vary.

## Experimental Raw Commands

The Remote screen includes an experimental raw HK command tester. It uses the
same configured receiver, device type, and zone as the normal remote, but lets
you type the XML `<name>` and optional `<para>` values directly.

Use it when you have a command captured from the Harman native app or want to
probe hidden receiver settings. For example, to investigate Harman Volume:

```txt
Command name: harman-volume
Param: Low
```

Other candidate command names to test:

- `harman-volume`
- `dolby-volume`
- `audio-effects`
- `audio`
- `volume-leveler`

Candidate Harman Volume params:

- `Off`
- `Low`
- `Medium`
- `High`
- `Max`
- `0`
- `1`
- `2`
- `3`

Leave "Wait for response" off for most probes. Turn it on only for commands you
expect to behave like `heart-alive`; otherwise the app will wait for a response
that may never arrive and then report a timeout.

Unsupported commands usually fail silently. Supported hidden commands may change
receiver settings immediately, so test while you can see or hear the receiver.

## Power-On Limitations

The `power-on` command is part of the protocol, but it can only be delivered if
the receiver is still listening on the network. Some firmware shuts down the
control server after standby or immediately after `power-off`; once port `10025`
is closed, this API cannot wake the receiver by itself.

Practical options:

- Prefer `sleep` over `off` on models that keep the network service alive during
  sleep.
- Use `heartAlive` or another low-impact command as a keep-awake experiment, but
  test per model because `heartAlive` is unsupported on some receivers.
- Use a non-HKAPI wake path, such as the physical remote, front-panel button,
  HDMI-CEC, IR blaster, or smart plug workflow, if the receiver enters deep
  standby.

## Discovery And State Limits

Current discovery scans the local subnet for open TCP port `10025`. That finds
candidate receivers but does not prove the service is Harman Kardon, identify a
model, or detect sleeping devices.

The API has no known endpoints for authoritative volume, mute, current source, or
playback state. UI state should be treated as optimistic unless a future
model-specific response parser proves otherwise.

## Protocol Verification

Use this script to inspect generated payloads:

```sh
npm run verify:protocol
```

It prints representative XML and full TCP payloads for selected commands.