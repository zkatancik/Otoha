import { homedir } from 'node:os';
import { join } from 'node:path';
import { startHomeListener } from './home-lan.js';
import { Bridge } from './bridge.js';
import { httpApp, privatePeer } from './http.js';

const port = Number(process.env.PORT || 3770);
const addresses = [...new Set((process.env.OTOHA_BIND || '127.0.0.1').split(',').map((s) => s.trim()))];
if (!addresses.length || addresses.some((ip) => !privatePeer(ip)))
  throw new Error('Use specific loopback, home LAN or Tailscale IPv4 addresses for OTOHA_BIND.');
const names = [
  ...addresses,
  'localhost',
  ...(process.env.OTOHA_HOSTNAMES || '').split(',').filter(Boolean),
];
const hosts = new Set(names.map((n) => n + ':' + port));
const bridge = new Bridge({
  address: process.env.HK_HOST,
  directory: process.env.OTOHA_DATA || join(homedir(), '.config', 'otoha'),
  wakeUrl: process.env.OTOHA_IR_WAKE_URL,
});
await bridge.init();
for (const address of addresses) {
  const listen = () => {
    const server = httpApp(bridge, hosts);
    server.once('error', (error) => {
      if (error.code === 'EADDRNOTAVAIL') {
        console.warn('Waiting for interface ' + address);
        setTimeout(listen, 10000);
      } else {
        console.error(error.message);
        process.exit(1);
      }
    });
    server.listen(port, address, () => console.log('Otoha listening at http://' + address + ':' + port));
  };
  listen();
}
if (process.platform === 'darwin' && process.env.OTOHA_LAN_INTERFACE && process.env.OTOHA_BRIDGE_ID) {
  startHomeListener(bridge, hosts, {
    iface: process.env.OTOHA_LAN_INTERFACE, port, id: process.env.OTOHA_BRIDGE_ID, fixed: addresses,
  });
}
