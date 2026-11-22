import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import http from 'node:http';
import { once } from 'node:events';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { frame, transmit, localIPv4, identify } from '../server/device.js';
import { Bridge } from '../server/bridge.js';
import { httpApp, privatePeer } from '../server/http.js';
import { inputs, remoteKeys } from '../public/catalog.js';

const stereo = {
  id: 'uuid:stereo', host: '192.168.1.123', model: 'HK 3770', profile: 'stereo', name: 'Stereo',
  location: 'http://192.168.1.123:8080/dd.xml', control: null,
};

test('HK37xx handset framing and model-specific commands', () => {
  const [header, xml] = frame(remoteKeys.harman).toString().split('\r\n\r\n');
  assert.ok(header.startsWith('POST avr HTTP/1.1\r\nHost: :10025\r\n'));
  assert.ok(xml.includes('<name>harman_volume</name><zone>Main Zone</zone><para></para>'));
  assert.ok(frame('heart-alive', '', '').includes('<zone></zone>'));
  assert.ok(frame(remoteKeys.standby).includes('<name>standby</name>'));
  assert.equal(inputs.find((s) => s.id === 'cd').wire, 'Disc');
  assert.equal(inputs.find((s) => s.id === 'phono').wire, 'Phono');
  const [utfHeader, utfXml] = frame('source-selection', 'A&B é').toString().split('\r\n\r\n');
  assert.ok(utfXml.includes('A&amp;B é'));
  assert.ok(utfHeader.endsWith('Content-Length: ' + Buffer.byteLength(utfXml)));
});

test('real TCP transport accepts fragmented heartbeat and rejects silent disconnect', async (t) => {
  let silentlyClose = false;
  const srv = net.createServer((socket) =>
    socket.once('data', () => {
      if (silentlyClose) return socket.end();
      socket.write('POST AVR HTTP/1.1\r\n\r\n<harman><avr><common><sta');
      setTimeout(() => socket.end('tus><name>heart-alive</name></status></common></avr></harman>'), 10);
    }),
  );
  srv.listen(0, '127.0.0.1');
  await once(srv, 'listening');
  t.after(() => srv.close());
  await transmit('127.0.0.1', [frame('heart-alive', '', '')], true, srv.address().port);
  silentlyClose = true;
  await assert.rejects(transmit('127.0.0.1', [frame('heart-alive', '', '')], true, srv.address().port));
});

test('discovery and HTTP binding are limited to home and private tunnel addresses', async () => {
  for (const ip of ['localhost', '127.0.0.1', '198.51.100.4', '192.168.1.999'])
    assert.equal(localIPv4(ip), false);
  for (const ip of ['0.0.0.0', '100.128.0.1', '100.63.1.2']) assert.equal(privatePeer(ip), false);
  assert.equal(privatePeer('100.106.215.78'), true);
  assert.equal(await identify('http://example.org/device.xml'), null);
});

test('unsupported actions, invalid network levels, and an unreachable receiver never report success', async () => {
  const bridge = new Bridge({ directory: '.' });
  for (const [action, value] of [
    ['__proto__'],
    ['constructor'],
    ['source', 'other'],
    ['network-volume', 120],
    ['network-volume', '20'],
  ]) {
    assert.throws(() => bridge.run(action, value), { status: 400 });
  }
  await assert.rejects(bridge.run('harman'), /unavailable/);
});

test('same-origin control boundary and ordinary UI entry point', async (t) => {
  const hosts = new Set();
  const commands = [];
  const server = httpApp(
    {
      snapshot: async () => ({ online: true }),
      run: async (a, v) => {
        commands.push([a, v]);
        return { message: 'sent' };
      },
    },
    hosts,
  );
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => server.close());
  const host = '127.0.0.1:' + server.address().port;
  hosts.add(host);
  const root = 'http://' + host;
  const home = await fetch(root);
  assert.match(await home.text(), /id="device-portrait"/);
  const art = await (await fetch(root + '/assets/hardware/catalog.json')).json();
  for (const label of ['HK 3770', 'AVR 171S/1710S', 'BDS 7773W', 'Onyx', 'Global Caché iTach Flex WiFi']) {
    assert.ok(art[label], label);
    const portrait = await fetch(root + '/assets/hardware/' + art[label] + '.webp');
    assert.equal(portrait.status, 200);
    assert.equal(portrait.headers.get('content-type'), 'image/webp');
  }
  const badHost = await new Promise((done, fail) =>
    http
      .get(root + '/api/state', { headers: { Host: 'somewhere.invalid' } }, (response) => {
        response.resume();
        done(response.statusCode);
      })
      .on('error', fail),
  );
  assert.equal(badHost, 403);
  const send = (origin) =>
    fetch(root + '/api/command', {
      method: 'POST',
      headers: { Origin: origin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'source', value: 'tv' }),
    });
  assert.equal((await send('http://outside.example')).status, 403);
  assert.equal((await send(root)).status, 200);
  assert.deepEqual(commands, [['source', 'tv']]);
});

test('synced Harman modes use the minimum cycle presses and forget interrupted sequences', async () => {
  const packets = [];
  const bridge = new Bridge({
    directory: '.',
    send: async (_host, frames) => packets.push(...frames.map((f) => f.toString())),
  });
  bridge.device = stereo;
  await assert.rejects(bridge.run('set-mode', 'Off'), { status: 409 });
  await bridge.run('sync-mode', 'High');
  assert.equal(packets.length, 1);
  await bridge.run('set-mode', 'Off');
  assert.equal(packets.filter((p) => p.includes('<name>harman_volume</name>')).length, 2);
  await bridge.run('set-mode', 'Off');
  assert.equal(packets.length, 3);
  await bridge.run('harman');
  assert.equal(bridge.trackedMode, 'High');
  bridge.send = async () => {
    throw new Error('connection closed');
  };
  await assert.rejects(bridge.run('set-mode', 'Low'), /interrupted/);
  assert.equal(bridge.trackedMode, null);
});

test('concurrent commands are delivered in order and source selection uses the handset payloads', async () => {
  const packets = [];
  const bridge = new Bridge({
    directory: '.',
    send: async (_host, frames) => packets.push(...frames.map((p) => p.toString())),
  });
  bridge.device = stereo;
  await Promise.all([
    bridge.run('source', 'phono'),
    bridge.run('quieter'),
    bridge.run('source', 'usb'),
    bridge.run('source', 'tv'),
  ]);
  assert.deepEqual(
    packets.map((p) => p.match(/<name>([^<]+)<\/name>/)[1]),
    ['source-selection', 'volume-down', 'source-selection', 'source-selection', 'source-selection'],
  );
  assert.deepEqual(
    packets.map((p) => p.match(/<para>([^<]*)<\/para>/)[1]),
    ['Phono', '', 'USB', 'iPod', 'TV'],
  );
  assert.equal(bridge.lastSource, 'tv');
  await bridge.run('standby');
  assert.equal(bridge.lastSource, null);
});

test('a missing heartbeat reply does not disable controls when both receiver services are reachable', async () => {
  const bridge = new Bridge({
    directory: '.',
    send: async () => {
      throw Object.assign(new Error('Receiver closed after write'), { frameSent: true });
    },
    renderer: async (_device, action) =>
      action === 'GetVolume' ? '<CurrentVolume>0</CurrentVolume>' : '<CurrentMute>0</CurrentMute>',
  });
  bridge.device = { ...stereo, control: 'http://192.168.1.123:8080/control' };
  bridge.trackedMode = 'High';
  bridge.lastSearch = Date.now();
  assert.equal((await bridge.read()).online, true);
  assert.equal(bridge.trackedMode, 'High');
  bridge.send = async () => {
    throw new Error('Connection refused');
  };
  assert.equal((await bridge.read()).online, false);
  assert.equal(bridge.trackedMode, null);
});

test('configured infrared wake works without a receiver TCP connection and surfaces emitter failures', async (t) => {
  let available = true;
  let requests = 0;
  const emitter = http.createServer((req, res) => {
    assert.equal(req.method, 'POST');
    assert.equal(req.url, '/learned-on');
    requests++;
    res.writeHead(available ? 204 : 503).end();
  });
  emitter.listen(0, '127.0.0.1');
  await once(emitter, 'listening');
  t.after(() => emitter.close());
  const directory = await mkdtemp(join(tmpdir(), 'otoha-infrared-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const bridge = new Bridge({ directory });
  bridge.saved = stereo;
  bridge.irOwner = stereo.id;
  assert.equal(await bridge.infraredWakeURL(), null);
  const url = 'http://127.0.0.1:' + emitter.address().port + '/learned-on';
  await writeFile(join(directory, 'ir-wake-url'), url + '\n');
  assert.equal(await bridge.infraredWakeURL(), url);
  const override = new Bridge({ directory, wakeUrl: 'http://127.0.0.1/env' });
  assert.equal(await override.infraredWakeURL(), 'http://127.0.0.1/env');
  bridge.trackedMode = 'Low';
  assert.match((await bridge.run('wake')).message, /Infrared wake requested/);
  assert.equal(bridge.trackedMode, null);
  available = false;
  await assert.rejects(bridge.run('wake'), /did not accept/);
  assert.equal(requests, 2);
});

test('a BroadLink wake sends one discrete command while the HK is offline', async (t) => {
  const directory = await mkdtemp(join(tmpdir(), 'otoha-broadlink-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const calls = [];
  const bridge = new Bridge({
    directory,
    sendBroadlink: async (configDirectory) => calls.push(configDirectory),
  });
  bridge.saved = stereo;
  bridge.irOwner = stereo.id;
  bridge.lastSearch = Date.now();
  await writeFile(join(directory, 'ir-wake-url'), 'broadlink:power-on\n');
  const state = await bridge.read();
  assert.equal(state.irWake, true);
  assert.equal(state.online, false);
  assert.deepEqual(calls, []);
  assert.equal((await bridge.run('wake')).message, 'Infrared wake requested.');
  assert.deepEqual(calls, [directory]);
  bridge.sendBroadlink = async () => { throw new Error('Hub unavailable'); };
  await assert.rejects(bridge.run('wake'), /Hub unavailable/);
});
