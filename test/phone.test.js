import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import http from 'node:http';
import { once } from 'node:events';
import { PhoneAccess } from '../server/phone-access.js';
import { gateway } from '../server/phone-gateway.js';

test('internet listener pairs once, authenticates every read and write, and forwards only receiver calls', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'otoha-phone-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const access = new PhoneAccess(dir);
  const received = [];
  const home = http.createServer((req, res) => {
    received.push([req.url, req.headers.origin, req.headers.authorization]);
    res.end('{"online":false}');
  });
  home.listen(0, '127.0.0.1');
  await once(home, 'listening');
  t.after(() => home.close());
  const origin = 'http://127.0.0.1:' + home.address().port;
  const edge = gateway(access, origin);
  edge.listen(0, '127.0.0.1');
  await once(edge, 'listening');
  t.after(() => edge.close());
  const url = 'http://127.0.0.1:' + edge.address().port;
  const post = (path, data, token) =>
    fetch(url + path, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: 'Bearer ' + token } : {}),
      },
      body: JSON.stringify(data),
    });
  assert.equal((await fetch(url + '/v1/state')).status, 401);
  assert.equal((await post('/v1/command', { action: 'standby' })).status, 401);
  const search = { action: 'search', receiverId: 'uuid:stereo' };
  assert.equal((await post('/v1/infrared', search)).status, 401);
  assert.equal((await post('/v1/devices', {})).status, 401);
  assert.equal((await post('/v1/link', { id: 'uuid:chosen' })).status, 401);
  assert.equal(received.length, 0);
  const code = access.issue();
  const pair = await post('/v1/pair', { code });
  assert.equal(pair.status, 200);
  const { token } = await pair.json();
  assert.equal((await post('/v1/pair', { code })).status, 403);
  assert.equal(new PhoneAccess(dir).accepts('Bearer ' + token), true);
  assert.equal((await post('/v1/command', { action: 'quieter' }, token)).status, 200);
  assert.equal((await post('/v1/infrared', search, token)).status, 200);
  assert.deepEqual(received, [['/api/command', origin, undefined], ['/api/infrared', origin, undefined]]);
  assert.equal(
    (await fetch(url + '/api/state', { headers: { Authorization: 'Bearer ' + token } })).status,
    404,
  );
  assert.equal(
    (await fetch(url + '/v1/pair', { method: 'DELETE', headers: { Authorization: 'Bearer ' + token } }))
      .status,
    200,
  );
  assert.equal(access.accepts('Bearer ' + token), false);
  const next = access.issue();
  for (let i = 0; i < 5; i++) access.pair('invalid');
  assert.equal(access.pair(next), null);
});
