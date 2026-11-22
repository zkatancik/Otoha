import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { PhoneAccess } from './phone-access.js';
import { privatePeer } from './http.js';

async function readBody(req, limit = 1024) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    bytes += chunk.length;
    if (bytes > limit) throw Object.assign(new Error(), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks));
  } catch {
    throw Object.assign(new Error(), { status: 400 });
  }
}

// This listener is the public tunnel origin. Every control and state read requires a paired phone.
export function gateway(access, upstream = 'http://127.0.0.1:3770') {
  return http.createServer({ headersTimeout: 6000, requestTimeout: 9000 }, async (req, res) => {
    const reply = (status, data) => {
      res.writeHead(status, {
        'Content-Type': 'application/json',
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      });
      res.end(JSON.stringify(data));
    };
    try {
      if (req.method === 'POST' && req.url === '/v1/pair') {
        if (req.headers['content-type']?.split(';')[0] !== 'application/json')
          return reply(415, { error: 'JSON required.' });
        const key = access.pair((await readBody(req))?.code);
        return key
          ? reply(200, { token: key })
          : reply(403, { error: 'Code invalid or expired. Generate a new code on your Mac.' });
      }
      if (!access.accepts(req.headers.authorization))
        return reply(401, { error: 'Pair this iPhone with Otoha.' });
      if (req.method === 'DELETE' && req.url === '/v1/pair') {
        access.revoke(req.headers.authorization);
        return reply(200, { message: 'This iPhone has been unpaired.' });
      }
      const paths = {
        'GET /v1/state': '/api/state',
        'POST /v1/command': '/api/command',
        'POST /v1/devices': '/api/devices',
        'POST /v1/link': '/api/link',
        'POST /v1/discover': '/api/discover',
        'POST /v1/infrared': '/api/infrared',
      };
      const target = paths[req.method + ' ' + req.url];
      if (!target) return reply(404, { error: 'Unknown endpoint.' });
      const options = { method: req.method, redirect: 'error', signal: AbortSignal.timeout(12000) };
      if (req.method === 'POST') {
        if (req.headers['content-type']?.split(';')[0] !== 'application/json')
          return reply(415, { error: 'JSON required.' });
        options.body = JSON.stringify(await readBody(req, target === '/api/infrared' ? 4096 : 1024));
        options.headers = { Origin: upstream, 'Content-Type': 'application/json' };
      }
      const result = await fetch(upstream + target, options);
      reply(result.status, await result.json());
    } catch (error) {
      reply(error.status || 502, {
        error: error.status ? 'Invalid request.' : 'Home bridge unavailable.',
      });
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const access = new PhoneAccess();
  const address = process.env.OTOHA_PHONE_BIND || '127.0.0.1';
  if (!privatePeer(address))
    throw new Error('Set a specific private IPv4 address for the tunnel origin.');
  gateway(access).listen(3772, address, () =>
    console.log('Otoha phone gateway listening at ' + address + ':3772'),
  );
}
