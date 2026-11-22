// Keep the Mac install bound to the chosen home interface as its Wi-Fi address changes.
import { networkInterfaces } from 'node:os';
import { spawn } from 'node:child_process';
import { localIPv4 } from './device.js';
import { httpApp } from './http.js';

export function startHomeListener(bridge, hosts, { iface, port, id, fixed }) {
  let address;
  let server;
  let advertisement;

  function stop() {
    advertisement?.kill();
    advertisement = undefined;
    if (server) {
      server.close();
      server.closeAllConnections();
      hosts.delete(address + ':' + port);
      server = undefined;
    }
    address = undefined;
  }

  function update() {
    const next = networkInterfaces()[iface]?.find(n => !n.internal && localIPv4(n.address))?.address;
    if (address !== next) {
      stop();
      address = next;
    }
    if (!address) return;
    if (!fixed.includes(address) && !server) {
      const listener = httpApp(bridge, hosts);
      server = listener;
      listener.once('error', error => {
        console.error('Home Wi-Fi listener:', error.message);
        if (server === listener) stop();
      });
      hosts.add(address + ':' + port);
      listener.listen(port, address, update);
      return;
    }
    if (!advertisement && (!server || server.listening)) {
      // An empty instance name tells Bonjour to use the Mac's display name.
      const child = spawn('/usr/bin/dns-sd', ['-i', iface, '-R', '', '_otoha._tcp', 'local.',
        String(port), 'id=' + id, 'ip=' + address, 'port=' + port], { stdio: 'ignore' });
      advertisement = child;
      child.on('error', error => console.error('Home Wi-Fi discovery:', error.message));
      child.on('close', () => { if (advertisement === child) advertisement = undefined; });
    }
  }

  update();
  const timer = setInterval(update, 5000);
  process.once('exit', () => { clearInterval(timer); advertisement?.kill(); });
  process.once('SIGTERM', () => process.exit(0));
  process.once('SIGINT', () => process.exit(0));
}
