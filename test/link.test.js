import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { Bridge } from '../server/bridge.js';
import { advertisement, frame, heartbeatReply, parseDescription, uniqueDevices } from '../server/device.js';
import { matchModel } from '../server/profiles.js';

function device(model, octet) {
  const host = '192.168.3.' + octet;
  return { ...matchModel(model), name: 'Room ' + octet, host, id: 'uuid:room-' + octet,
    location: 'http://' + host + ':8080/dd.xml', control: null };
}

async function installation(t, initial) {
  const directory = await mkdtemp(join(tmpdir(), 'otoha-link-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const lan = { devices: initial, writes: [], scans: 0 };
  const options = {
    directory,
    scan: async () => { lan.scans++; return lan.devices; },
    describe: async url => lan.devices.find(d => d.location === url),
    send: async (host, frames, heartbeat) => {
      lan.writes.push({ host, text: frames[0].toString(), heartbeat });
      if (host === lan.offline) throw new Error('Not reachable');
    },
  };
  return { bridge: new Bridge(options), options, lan };
}

test('all five wire profiles and regional model aliases retain their identity', () => {
  for (const [model, target, tag] of [
    ['HK 3700', 'avr', 'avr'], ['AVR 3700', 'AVR', 'avr'], ['AVR 151S/1510S', 'AVR', 'avr'],
    ['AVR 171/230C', 'AVR', 'avr'], ['BDS 7773W', 'HK_APP', 'bds'], ['BDS 280S', 'BDS', 'bds'],
    ['HK Aura', 'MM', 'mm'], ['HK Onyx', 'MM', 'mm'],
  ]) {
    const wire = frame('heart-alive', '', '', matchModel(model).profile).toString();
    assert.ok(wire.startsWith('POST ' + target + ' HTTP/1.1\r\n'));
    assert.ok(wire.includes('<harman><' + tag + '><common>'));
  }
  for (const other of ['AVR 9999', 'HK Onyx Studio 8', 'Aura Studio 2', 'SB26', 'Omni 20'])
    assert.equal(matchModel(other), null);
  const xml = '<harman><avr><common><control><name>heart-alive</name><zone>Main Zone</zone></control></common></avr></harman>';
  assert.equal(heartbeatReply(xml, 'avr'), true);
  assert.equal(heartbeatReply(xml, 'mm'), false);
  assert.equal(heartbeatReply(frame('heart-alive', '', '', 'avr').toString(), 'avr'), false);
});

test('discovery accepts the G3 vendor signature, and validates descriptor identity and sender', () => {
  const location = new URL('http://192.168.3.10:8080/description.xml');
  const xml = '<root><device><manufacturer>Harman Kardon</manufacturer><modelName>HK Aura </modelName>' +
    '<friendlyName>Room &amp; TV</friendlyName><UDN>uuid:aura</UDN><service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>' +
    '<controlURL>http://192.168.3.99/ctrl</controlURL></service></device></root>';
  const aura = parseDescription(xml, location);
  assert.equal(aura.model, 'Aura');
  assert.equal(aura.name, 'Room & TV');
  assert.equal(aura.control, null);
  assert.equal(parseDescription(xml.replace('Harman Kardon', 'Another manufacturer'), location), null);
  const response = 'NOTIFY * HTTP/1.1\r\nNTS: ssdp:alive\r\nSERVER: Harman Kardon BDS G3 UPnP/1.0 product/1\r\n' +
    'NT: harman-com:service:remote-controller:1\r\nUSN: uuid:00000000-0000-0000-0000001c5021e254\r\nLOCATION: http://192.168.3.20:10025/remote-controller\r\n';
  const bds = advertisement(response, '192.168.3.20').device;
  assert.equal(bds.model, 'BDS G3');
  assert.equal(advertisement(response, '192.168.3.30'), null);
  assert.equal(advertisement(response.replace('ssdp:alive', 'ssdp:byebye'), '192.168.3.20'), null);
  assert.deepEqual(uniqueDevices([null, aura, bds, { ...aura, advertised: true }]).map(d => d.id).sort(), [aura.id, bds.id].sort());
});

test('first setup requires a choice, switches profiles, and rejects stale commands and failed links', async t => {
  const stereo = device('HK 3770', 8), avr = device('AVR 161S', 9), aura = device('Aura Plus', 10);
  const { bridge, lan, options } = await installation(t, [stereo, avr, aura]);
  await bridge.init();
  assert.equal((await bridge.snapshot()).linked, false);
  assert.equal(lan.scans, 0);
  assert.equal((await bridge.listDevices()).length, 3);
  assert.equal(lan.writes.length, 0);
  await assert.rejects(bridge.link('arbitrary-host'), { status: 409 });
  assert.equal((await bridge.link(avr.id)).online, true);
  assert.ok(lan.writes.every(w => w.heartbeat && w.host === avr.host));
  await bridge.run('source', 'usb', avr.id);
  assert.match(lan.writes.at(-1).text, /^POST AVR[\s\S]*<para>USB<\/para>/);
  assert.throws(() => bridge.run('harman'), { status: 400 });
  await bridge.tail;
  lan.offline = aura.host;
  await assert.rejects(bridge.link(aura.id), { status: 503 });
  assert.equal(bridge.saved.id, avr.id);
  assert.equal(JSON.parse(await readFile(join(options.directory, 'receiver.json'))).id, avr.id);
  lan.offline = null;
  const next = await bridge.link(aura.id);
  assert.equal(next.lastSource, null);
  assert.equal(next.sources.length, 0);
  assert.throws(() => bridge.run('standby', undefined, avr.id), { status: 409 });
  assert.throws(() => bridge.run('louder', undefined, aura.id), { status: 400 });
  assert.throws(() => bridge.run('speaker-volume', '101'), { status: 400 });
  await bridge.run('speaker-volume', '12', aura.id);
  assert.match(lan.writes.at(-1).text, /^POST MM[\s\S]*<name>set_system_volume<\/name><zone>Main Zone<\/zone><para>12<\/para>/);
});

test('legacy selection follows its identity through DHCP changes and survives an offline restart', async t => {
  const original = device('HK 3770', 6);
  const moved = { ...device('HK 3770', 11), id: original.id };
  const other = { ...original, id: 'uuid:other' };
  const { bridge, lan, options } = await installation(t, [other, moved]);
  await writeFile(join(options.directory, 'receiver.json'), JSON.stringify({
    id: original.id, host: original.host, location: original.location, control: original.control,
  }));
  await bridge.init();
  assert.equal(bridge.device.id, original.id);
  assert.equal(bridge.device.host, moved.host);
  assert.equal(bridge.irOwner, original.id);
  lan.devices = [other];
  const restarted = new Bridge(options);
  await restarted.init();
  const state = await restarted.snapshot();
  assert.equal(state.online, false);
  assert.equal(state.device.id, original.id);
  assert.equal(restarted.device, null);
  await assert.rejects(restarted.run('standby'), /unavailable/);
  assert.equal(lan.writes.length, 0);
});

test('silent AVR 170 can link by verified identity, while an unrelated reply fails', async t => {
  const avr = device('AVR 170', 13);
  const { bridge } = await installation(t, [avr]);
  await bridge.listDevices();
  let receivedData = true;
  bridge.send = async () => { throw Object.assign(new Error('No heartbeat'), { frameSent: true, receivedData }); };
  await assert.rejects(bridge.link(avr.id), { status: 503 });
  receivedData = false;
  assert.equal((await bridge.link(avr.id)).online, true);
  bridge.scannedAt = 0;
  await assert.rejects(bridge.link(avr.id), { status: 409 });
});

test('a link in progress isolates commands and two simultaneous selections', async t => {
  const first = device('HK 3700', 21), second = device('BDS 277', 22);
  const { bridge } = await installation(t, [first, second]);
  await bridge.listDevices();
  await bridge.link(first.id);
  const started = Promise.withResolvers(), release = Promise.withResolvers();
  bridge.send = async () => { started.resolve(); await release.promise; };
  const switching = bridge.link(second.id);
  await started.promise;
  assert.throws(() => bridge.run('mute', undefined, first.id), { status: 409 });
  await assert.rejects(bridge.link(first.id), { status: 409 });
  release.resolve();
  assert.equal((await switching).device.id, second.id);
});

test('a legacy cache without a device ID can be shown offline and upgraded upon identification', async t => {
  const old = device('HK 3770', 15);
  const { bridge, options, lan } = await installation(t, []);
  await writeFile(join(options.directory, 'receiver.json'), JSON.stringify({ host: old.host, location: old.location }));
  await bridge.init();
  const state = await bridge.snapshot();
  assert.equal(state.linked, true);
  assert.equal(typeof state.device.id, 'string');
  assert.equal(state.online, false);
  lan.devices = [old];
  await bridge.locate();
  assert.equal((await bridge.snapshot()).device.id, old.id);
  assert.equal(JSON.parse(await readFile(join(options.directory, 'receiver.json'))).id, old.id);
});
