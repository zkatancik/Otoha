import net from 'node:net';
import dgram from 'node:dgram';
import { matchModel, profiles } from './profiles.js';
import { networkInterfaces } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';

export function localIPv4(ip) {
  return net.isIPv4(ip) && /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ip);
}

export const textOf = (xml, tag) =>
  xml.match(new RegExp('<' + tag + '>([^<]*)</' + tag + '>', 'i'))?.[1]?.trim();
const escape = (value) =>
  String(value).replace(
    /[<>&"']/g,
    (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[c],
  );

export function frame(name, para = '', zone = 'Main Zone', profile = 'stereo') {
  const { target, tag, agent } = profiles[profile];
  const xml =
    '<?xml version="1.0" encoding="UTF-8"?><harman><' + tag + '><common><control><name>' +
    escape(name) +
    '</name><zone>' +
    escape(zone) +
    '</zone><para>' +
    escape(para) +
    '</para></control></common></' + tag + '></harman>';
  return Buffer.from(
    'POST ' + target + ' HTTP/1.1\r\nHost: :10025\r\nUser-Agent: ' + agent + '\r\nContent-Length: ' +
      Buffer.byteLength(xml) +
      '\r\n\r\n' +
      xml,
  );
}

export function heartbeatReply(response, profile) {
  const tag = profiles[profile].tag;
  const body = response.match(new RegExp('<harman>\\s*<' + tag + '>\\s*<common>\\s*<(status|control)>([\\s\\S]*?)</\\1>', 'i'));
  if (!body || textOf(body[2], 'name') !== 'heart-alive') return false;
  if (body[1].toLowerCase() === 'status') return true;
  // The AVR application parses a control reply carrying the receiver's zone. A request echo has none.
  return profile === 'avr' && ['Main Zone', 'Zone 2'].includes(textOf(body[2], 'zone'));
}

export function transmit(host, frames, heartbeat = false, port = 10025) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host, port });
    let frameSent = false;
    let receivedData = false;
    const finish = (error) => {
      clearTimeout(deadline);
      socket.destroy();
      if (error) reject(Object.assign(error, { frameSent, receivedData }));
      else resolve();
    };
    const deadline = setTimeout(() => finish(new Error('The receiver did not respond.')), 1600);
    socket.on('error', finish);
    socket.once('close', () => {
      clearTimeout(deadline);
      reject(Object.assign(new Error('Receiver connection closed.'), { frameSent, receivedData }));
    });
    if (heartbeat) {
      let feedback = '';
      const profile = Object.keys(profiles).find(key => frames[0].subarray(0, 24).toString().startsWith('POST ' + profiles[key].target + ' '));
      socket.on('data', (chunk) => {
        feedback += chunk.toString('utf8');
        receivedData = true;
        if (profile && heartbeatReply(feedback, profile)) finish();
        else if (feedback.length > 32768) finish(new Error('Unexpected receiver reply.'));
      });
    }
    socket.once('connect', async () => {
      try {
        for (const [index, packet] of frames.entries()) {
          if (index) await delay(50);
          if (socket.destroyed) return;
          await new Promise((done, fail) => socket.write(packet, (err) => (err ? fail(err) : done())));
        }
        frameSent = true;
        if (!heartbeat) socket.end(() => finish());
      } catch (error) {
        finish(error);
      }
    });
  });
}

export async function xmlRequest(url, options = {}) {
  const res = await fetch(url, { ...options, redirect: 'error', signal: AbortSignal.timeout(1700) });
  if (!res.ok) throw new Error('Receiver returned HTTP ' + res.status);
  const parts = [];
  let size = 0;
  for await (const chunk of res.body) {
    size += chunk.byteLength;
    if (size > 65536) throw new Error('Unexpected device description.');
    parts.push(chunk);
  }
  return Buffer.concat(parts).toString('utf8');
}

function descriptionURL(location) {
  try {
    const url = new URL(location);
    if (url.protocol === 'http:' && localIPv4(url.hostname) && !url.username && !url.password) return url;
  } catch {}
  return null;
}

export function parseDescription(xml, url) {
  const manufacturer = textOf(xml, 'manufacturer') || '';
  if (!/^harman[\s/.-]*kardon(?:\s+international(?: industries)?(?:,? inc\.?)?)?$/i.test(manufacturer)) return null;
  const name = textOf(xml, 'modelName');
  const friendly = textOf(xml, 'friendlyName');
  const model = matchModel(name && !/^none$/i.test(name) ? name : friendly);
  const id = textOf(xml, 'UDN');
  if (!model || !id || id.length > 200) return null;
  const service = (xml.match(/<service>[\s\S]*?<\/service>/gi) || []).find(s =>
    textOf(s, 'serviceType') === 'urn:schemas-upnp-org:service:RenderingControl:1');
  const path = service && textOf(service, 'controlURL');
  let control = null;
  if (path) {
    let candidate;
    try { candidate = descriptionURL(new URL(path, url)); } catch {}
    if (candidate?.origin === url.origin) control = candidate.href;
  }
  const label = (friendly || model.model).slice(0, 96).replace(/&amp;/g, '&');
  return { ...model, name: label, id, host: url.hostname, location: url.href, control };
}

export async function identify(location) {
  const url = descriptionURL(location);
  return url ? parseDescription(await xmlRequest(url), url) : null;
}

// Some BDS receivers advertise the handset endpoint directly, without a UPnP XML document.
export function advertisement(message, peer) {
  const header = message.toString();
  const alive = /^NOTIFY \* HTTP\/1\.1/i.test(header) && /^nts:[ \t]*ssdp:alive\s*$/im.test(header);
  if (!alive && !/^HTTP\/1\.[01] 200\b/i.test(header)) return null;
  const url = descriptionURL(/^location:[ \t]*(\S+)/im.exec(header)?.[1]);
  if (!url || url.hostname !== peer) return null;
  const server = /^server:[ \t]*Harman Kardon (BDS (?:G3|235|535|280S?|580S?))(?=\s|\/|$)/im.exec(header);
  const id = /^usn:[ \t]*(uuid:[^:\s]+)/im.exec(header)?.[1];
  let device = null;
  if (server && id && id.length <= 200) {
    const markedS = /^server:[^\r\n]*\/80s\b/im.test(header) && /^BDS (280|580)$/i.test(server[1]);
    const model = matchModel(server[1] + (markedS ? 'S' : ''));
    device = { ...model, name: model.model, id, host: peer, location: url.href, control: null, advertised: true };
  }
  return { location: url.href, device };
}

export function uniqueDevices(results) {
  // A receiver may advertise the tunnel and a renderer at different URLs.
  const seenIds = new Set();
  const seenHosts = new Set();
  return results.filter(Boolean).sort((a, b) => Number(!!b.control) - Number(!!a.control)
    || Number(!!a.advertised) - Number(!!b.advertised) || a.location.localeCompare(b.location))
    .filter(d => {
      if (seenIds.has(d.id) || seenHosts.has(d.host)) return false;
      seenIds.add(d.id);
      seenHosts.add(d.host);
      return true;
    }).sort((a, b) => a.name.localeCompare(b.name) || a.host.localeCompare(b.host, 'en', { numeric: true }));
}

export async function discover() {
  const entries = Object.values(networkInterfaces()).flat().filter(n => n && !n.internal && localIPv4(n.address));
  const pending = new Map();
  const advertised = [];
  const sockets = [];
  const targets = ['harman-com:service:remote-controller:1', 'urn:schemas-upnp-org:device:MediaRenderer:1',
    'upnp:rootdevice', '"upnp:rootdevice"', 'upnp:all'];
  const receive = (message, peer) => {
    const entry = advertisement(message, peer.address);
    if (!entry) return;
    if (entry.device && advertised.length < 100) advertised.push(entry.device);
    if (!pending.has(entry.location) && pending.size < 80 && !(entry.device && new URL(entry.location).port === '10025')) {
      pending.set(entry.location, identify(entry.location).catch(() => null));
    }
  };
  if (entries.length) {
    const multicast = dgram.createSocket({ type: 'udp4', reuseAddr: true });
    sockets.push(multicast);
    multicast.on('error', () => {});
    multicast.on('message', receive);
    multicast.bind(1900, () => {
      for (const { address } of entries) {
        try { multicast.addMembership('239.255.255.250', address); } catch {}
      }
    });
  }
  const queries = targets.map(target => Buffer.from(
    'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: ' + target + '\r\n\r\n'));
  const ready = [];
  function search(socket) {
    for (const query of queries) socket.send(query, 1900, '239.255.255.250');
  }
  for (const { address } of entries) {
    const socket = dgram.createSocket('udp4');
    sockets.push(socket);
    socket.on('error', () => {});
    socket.on('message', receive);
    socket.bind(0, address, () => {
      try {
        socket.setMulticastInterface(address);
        ready.push(socket);
        search(socket);
      } catch { /* The interface may disappear during discovery. */ }
    });
  }
  // M-SEARCH is UDP. A second request also helps receivers that miss the first multicast.
  await delay(600);
  for (const socket of ready) {
    try { search(socket); } catch {}
  }
  await delay(1600);
  for (const socket of sockets) {
    try { socket.close(); } catch {}
  }
  return uniqueDevices([...(await Promise.all(pending.values())), ...advertised]);
}

export async function rendering(device, action, fields = {}) {
  const type = 'urn:schemas-upnp-org:service:RenderingControl:1';
  const parameters = Object.entries({ InstanceID: 0, Channel: 'Master', ...fields })
    .map(([k, v]) => '<' + k + '>' + escape(v) + '</' + k + '>')
    .join('');
  const body =
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:' +
    action +
    ' xmlns:u="' +
    type +
    '">' +
    parameters +
    '</u:' +
    action +
    '></s:Body></s:Envelope>';
  const response = await xmlRequest(device.control, {
    method: 'POST',
    headers: {
      'Content-Type': 'text/xml; charset="utf-8"',
      SOAPAction: '"' + type + '#' + action + '"',
    },
    body,
  });
  if (!response.includes(action + 'Response')) throw new Error('Receiver did not confirm the request.');
  return response;
}
