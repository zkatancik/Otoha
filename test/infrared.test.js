import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import dns from 'node:dns';
import http from 'node:http';
import { mkdtemp, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Bridge } from '../server/bridge.js';
import { httpApp } from '../server/http.js';
import { localBlasters } from '../server/infrared.js';
import { manualBlaster, sendWebhook } from '../server/ir-webhook.js';
import { gateway } from '../server/phone-gateway.js';

const receiver = { id: 'uuid:stereo', model: 'HK 3770', profile: 'stereo' };
const broadlink = { kind: 'broadlink', mac: '010203040506', host: '192.168.2.15', model: 'BroadLink RM4 mini' };
const itach = { kind: 'itach', mac: '000c1e001234', host: '192.168.2.16', model: 'Global Caché iTach IP2IR' };

async function fixture(t, devices) {
  const directory = await mkdtemp(join(tmpdir(), 'otoha-blasters-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const calls = [];
  const drivers = {
    discover: async () => { calls.push('discover'); return devices; },
    check: async device => { calls.push('check ' + device.mac); },
    send: async device => { calls.push('send ' + device.mac); },
  };
  const restart = () => {
    const bridge = new Bridge({ directory, blasters: drivers, scan: async () => [] });
    bridge.saved = receiver;
    bridge.irOwner = receiver.id;
    bridge.lastSearch = Date.now();
    return bridge;
  };
  return { bridge: restart(), restart, directory, drivers, calls };
}

test('consent links one verified IR remote, persists across restarts, and wakes only on demand', async t => {
  const { bridge, restart, calls } = await fixture(t, [broadlink, broadlink]);
  const hosts = new Set();
  const server = httpApp(bridge, hosts).listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => server.close());
  const host = '127.0.0.1:' + server.address().port;
  const origin = 'http://' + host;
  hosts.add(host);
  const submit = (payload, from = origin) => fetch(origin + '/api/infrared', {
    method: 'POST', headers: { Origin: from, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const state = await (await fetch(origin + '/api/state')).json();
  assert.equal(state.infrared.phase, 'idle');
  assert.equal(state.irWake, false);
  assert.equal((await fetch(origin + '/api/infrared')).status, 404);
  const search = { action: 'search', receiverId: receiver.id };
  assert.equal((await submit(search, 'https://other.example')).status, 403);
  assert.equal((await submit({ receiverId: receiver.id })).status, 400);
  assert.equal((await submit({ ...search, receiverId: 'different' })).status, 409);
  assert.deepEqual(calls, []);
  assert.equal((await (await submit(search)).json()).phase, 'searching');
  await bridge.infrared.job;
  assert.deepEqual(calls, ['discover', 'check ' + broadlink.mac]);
  const next = restart();
  assert.equal((await next.snapshot()).infrared.label, broadlink.model);
  assert.equal((await next.snapshot()).irWake, true);
  assert.equal((await next.run('wake', undefined, receiver.id)).message, 'Infrared wake requested.');
  assert.deepEqual(calls, ['discover', 'check ' + broadlink.mac, 'send ' + broadlink.mac]);
  assert.equal((await next.infrared.update(receiver.id, 'forget')).phase, 'idle');
  assert.equal((await restart().snapshot()).irWake, false);
});

test('multiple results require a discovered identity and failed checks are retryable', async t => {
  const { bridge, drivers, calls } = await fixture(t, []);
  const { infrared } = bridge;
  await infrared.update(receiver.id, 'search');
  await infrared.job;
  assert.match((await infrared.status(receiver.id)).message, /No compatible blaster/);
  let finish;
  drivers.discover = () => new Promise(resolve => { finish = resolve; });
  await infrared.update(receiver.id, 'search');
  assert.equal((await infrared.update(receiver.id, 'search')).phase, 'searching');
  finish([itach, { ...itach, host: '203.0.113.5' }, broadlink, itach]);
  await infrared.job;
  const state = await infrared.status(receiver.id);
  assert.equal(state.phase, 'choose');
  assert.equal(state.devices.length, 2);
  await assert.rejects(infrared.update(receiver.id, 'select', 'arbitrary-target'), { status: 409 });
  drivers.check = async () => { throw new Error('Device lock is on.'); };
  await infrared.update(receiver.id, 'select', state.devices[0].id);
  await infrared.job;
  assert.match((await infrared.status(receiver.id)).message, /Device lock/);
  assert.equal(await infrared.saved(receiver.id), null);
  drivers.discover = async () => [itach];
  drivers.check = async device => assert.deepEqual(device, itach);
  await infrared.update(receiver.id, 'search');
  await infrared.job;
  assert.equal((await bridge.snapshot()).infrared.label, itach.model);
  drivers.send = async () => { throw new Error('No transmission confirmation'); };
  await assert.rejects(bridge.run('wake'), /No transmission confirmation/);
  assert.deepEqual(calls, ['discover']);
});

test('a search cannot attach to another receiver or replace an existing manual configuration', async t => {
  const { bridge, directory, drivers, calls } = await fixture(t, [itach]);
  const { infrared } = bridge;
  let finish;
  drivers.discover = () => new Promise(resolve => { finish = resolve; });
  await infrared.update(receiver.id, 'search');
  const other = { ...receiver, id: 'second' };
  bridge.saved = other;
  finish([itach]);
  await infrared.job;
  assert.equal(await infrared.saved(receiver.id), null);
  assert.equal(await infrared.saved(other.id), null);
  bridge.saved = receiver;
  await writeFile(join(directory, 'ir-wake-url'), 'broadlink:power-on');
  await assert.rejects(infrared.update(receiver.id, 'search'), { status: 409 });
  assert.equal((await bridge.snapshot()).infrared.phase, 'external');
  bridge.saved = { ...other, model: 'HK 3700' };
  await assert.rejects(infrared.update(other.id, 'search'), { status: 409 });
  assert.equal((await bridge.read()).infrared, undefined);
  assert.deepEqual(calls, []);
});

test('Bonjour blasters participate in the same opt-in picker and retain their advertised port on wake', async t => {
  const devices = [
    { ...itach, kind: 'remo', model: 'Nature Remo', port: 80 },
    { ...broadlink, kind: 'tasmota', model: 'Tasmota IR', port: 8081 },
    { ...itach, kind: 'irkit', model: 'IRKit', port: 80, mac: '010000000003' },
  ];
  const { bridge, restart, drivers, calls } = await fixture(t, [
    ...devices, { ...devices[0], mac: '010000000004', port: 65536 },
  ]);
  const setup = bridge.infrared;
  await setup.update(receiver.id, 'search');
  await setup.job;
  const state = await setup.status(receiver.id);
  assert.equal(state.phase, 'choose');
  assert.equal(state.devices.length, 3);
  assert.deepEqual(calls, ['discover']);
  await setup.update(receiver.id, 'select', state.devices.find(d => d.label === 'Tasmota IR').id);
  await setup.job;
  let sent;
  drivers.send = async device => { sent = device; };
  const next = restart();
  await next.run('wake', undefined, receiver.id);
  assert.deepEqual(sent, devices[1]);
});

test('Not listed links through the phone gateway, survives restart and posts only when Power on is used', async t => {
  const { bridge, calls, restart, drivers } = await fixture(t, []);
  const listen = async server => {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    t.after(() => server.close());
    return 'http://127.0.0.1:' + server.address().port;
  };
  let status = 204;
  const posted = [];
  const emitter = await listen(http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    posted.push([req.method, req.url, Buffer.concat(chunks).length]);
    res.writeHead(status, { Location: '/second-request' }).end();
  }));
  const secretPath = '/api/webhook/' + 'example'.repeat(160);
  const url = 'http://unlisted.local' + secretPath;
  // Route this test controller to a loopback server, including its actual request and response.
  const request = http.request;
  const transport = t.mock.method(http, 'request', (target, options, callback) => {
    assert.equal(target.href, url);
    return request(new URL(target.pathname, emitter), options, callback);
  });
  drivers.send = localBlasters.send;
  const hosts = new Set();
  const home = await listen(httpApp(bridge, hosts));
  hosts.add(new URL(home).host);
  const phone = await listen(gateway({ accepts: header => header === 'Bearer paired-test' }, home));
  const submit = (action, extra = {}) => fetch(phone + '/v1/infrared', {
    method: 'POST', headers: { Authorization: 'Bearer paired-test', 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, receiverId: receiver.id, ...extra }),
  });
  const response = await submit('manual', { url });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { phase: 'linked', label: 'Custom IR blaster', receiverId: receiver.id });
  assert.equal((await stat(bridge.infrared.file(receiver.id))).mode & 0o777, 0o600);
  const next = restart();
  const state = await next.snapshot();
  assert.equal(state.online, false);
  assert.equal(state.irWake, true);
  assert.ok(!JSON.stringify(state).includes('example'));
  assert.deepEqual(calls, []);
  assert.equal(transport.mock.callCount(), 0);
  await next.run('wake', undefined, receiver.id);
  assert.deepEqual(posted, [['POST', secretPath, 0]]);
  for (status of [307, 500]) await assert.rejects(next.run('wake'), /webhook did not accept/);
  assert.deepEqual(posted, Array(3).fill(['POST', secretPath, 0]));
  assert.equal((await submit('manual', { url })).status, 200);
  assert.equal((await submit('manual', { url: url + 'other' })).status, 409);
  assert.equal((await submit('forget')).status, 200);
  assert.equal((await restart().snapshot()).irWake, false);
});

test('manual setup validates local endpoints without exposing their secrets', async t => {
  const { bridge, calls } = await fixture(t, []);
  const setup = bridge.infrared;
  for (const address of ['http://127.0.0.1', 'http://[::1]', 'http://169.254.1.1', 'https://example.org',
    'https://user:pass@home.local', 'ftp://10.0.0.1', 'http://home.local/#fragment', 'broken']) {
    await assert.rejects(setup.update(receiver.id, 'manual', undefined, address + '/private-key'), error =>
      error.status === 400 && !error.message.includes('private-key'));
  }
  assert.equal(await setup.saved(receiver.id), null);
  assert.deepEqual(calls, []);
  const device = manualBlaster('https://controller.local/power/private-key');
  t.mock.method(dns, 'lookup', (host, options, callback) => callback(null, '127.0.0.1', 4));
  await assert.rejects(sendWebhook(device), error => error.message.includes('Could not reach') && !error.message.includes('private-key'));
  assert.equal(dns.lookup.mock.callCount(), 1);
});

test('manual setup respects active discovery, the selected receiver, and a competing link', async t => {
  const { bridge, drivers } = await fixture(t, []);
  const setup = bridge.infrared;
  const url = 'http://192.168.1.20/on';
  const link = (address = url) => setup.update(receiver.id, 'manual', undefined, address);
  let finish;
  drivers.discover = () => new Promise(resolve => { finish = resolve; });
  await setup.update(receiver.id, 'search');
  await assert.rejects(link(), { status: 409 });
  finish([itach, broadlink]);
  await setup.job;
  await assert.rejects(setup.update('other', 'manual', undefined, url), { status: 409 });
  const [first, second] = await Promise.allSettled([link(), link(url + 'other')]);
  assert.equal(first.value.phase, 'linked');
  assert.equal(second.reason.status, 409);
  assert.equal((await setup.saved(receiver.id)).url, url);
  assert.equal(await setup.saved('other'), null);
});
