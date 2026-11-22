# Legacy browser remote

These tools run the earlier browser remote and support installations of older iPhone builds. The current iPhone app communicates directly with the receiver. The pairing and gateway commands here apply to older builds only.

Run command-line examples from the repository root. The Finder launchers are in this directory.

## Advanced bridge setup

Use Node.js 22 or newer. No package installation or build is required.

```sh
npm start
```

The bridge uses SSDP and the Harman remote-service advertisement. It remembers the linked device in `receiver.json` under `~/.config/otoha`. Set `HK_HOST` to include a known receiver address when locating devices.

```sh
HK_HOST=192.168.1.243 npm start
npm test
```

### Run at login on a Mac

The installer needs Python 3, Node.js and the Xcode command-line tools. Install Otoha from a checkout that will stay on the Mac.

```sh
npm run install:mac -- --lan
```

The installer prints the local and home Wi-Fi URLs. Add `--tailscale` to include the private tailnet URL. The Mac’s Tailscale URL works from a phone on cellular with Tailscale connected. The browser remote can also use this optional tailnet connection. Older iPhone builds with a pairing screen use the HTTPS gateway below for off-home access.

Allow **Otoha Bridge** in the macOS Local Network prompt. This allows the background agent to reach the receiver. The setting is under **System Settings → Privacy & Security → Local Network**. After granting access, press **Receiver → Locate devices**. The installer creates its app in `~/Applications`, its login service in `~/Library/LaunchAgents`, and its logs in `~/Library/Logs/Otoha`. The bridge runs while the Mac is awake and the user session is logged in. A receiver with an updated DHCP address can be rediscovered. The Mac installer follows address changes on the selected home network interface and advertises the bridge with Bonjour. If you switch the Mac between Wi-Fi and a cable, reopen **Set Up Otoha.command** to select the new connection.

To restart after a source update, run `launchctl kickstart -k "gui/$(id -u)/com.otoha.stereo-bridge"`. To stop the login service, run `launchctl bootout "gui/$(id -u)/com.otoha.stereo-bridge"`. To remove autostart, also remove its `com.otoha.stereo-bridge.plist` from your LaunchAgents folder.

### Native iPhone gateway

For optional access away from home, run the authenticated phone gateway alongside the home bridge. With a tunnel connector on the same Mac:

```sh
python3 scripts/install-phone-gateway.py --bind 127.0.0.1
npm run pair:iphone
```

In Cloudflare, add a published application route for the hostname `otoharemote.com` to the tunnel, using the HTTP service `http://127.0.0.1:3772` for the loopback installation above. For an existing gateway bound to a LAN address, use that gateway address on port 3772. The domain needs a proxied DNS record pointing to the tunnel. Leave the home bridge on its private interfaces on port 3770. [Cloudflare Tunnel DNS records](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/)

Keep the Mac awake with the home bridge, phone gateway, and tunnel running. For a self-hosted gateway on another domain, expand **Gateway address** before pairing.

### Other home hosts

`OTOHA_BIND` accepts a comma-separated list of specific loopback, LAN, and Tailscale IPv4 addresses on the bridge computer. `OTOHA_HOSTNAMES` allows additional DNS names. The default bind is loopback. `PORT` defaults to 3770. `OTOHA_DATA` changes the cache directory.

Control access follows the home network and tailnet ACLs. Devices allowed to reach the listening addresses can control the stereo. Otoha validates the HTTP Host, the browser Origin, and a fixed set of receiver commands. The production configuration uses private interfaces.

### Infrared wake

With an HK 3770 linked, open **Power → Set up infrared wake** on iPhone or in the browser. The guide covers BroadLink RM, IRKit, Nature Remo models with a local API, Tasmota IR transmitters, and Global Caché iTach IP2IR, WF2IR and Flex IR hubs. **Find and link a blaster** starts an optional search on your home network. A single match is configured automatically with the HK 3770’s discrete On signal. If several hubs answer, choose the one by your stereo. The usual **Power on** button then works from standby. The iPhone app sends commands on your home Wi-Fi. For another controller, choose **Not listed** and link a local webhook that sends the learned On command. [Legacy infrared setup](infrared-wake.md)
