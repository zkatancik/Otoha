import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { isIP } from 'node:net';
import { localIPv4 } from './device.js';

export function privatePeer(ip) {
  return (
    ip === '127.0.0.1' ||
    localIPv4(ip) ||
    (/^100\./.test(ip) &&
      Number(ip.split('.')[1]) >= 64 &&
      Number(ip.split('.')[1]) <= 127 &&
      isIP(ip) === 4)
  );
}
const run = promisify(execFile);
const qrScript = fileURLToPath(new URL('../scripts/phone-code.jxa', import.meta.url));
const types = {
  html: 'text/html; charset=utf-8',
  css: 'text/css',
  js: 'text/javascript',
  svg: 'image/svg+xml',
  webmanifest: 'application/manifest+json',
  png: 'image/png',
  webp: 'image/webp',
  json: 'application/json',
  woff2: 'font/woff2',
};
const root = new URL('../public/', import.meta.url);
const json = (res, status, data) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data));
};

export function httpApp(bridge, hosts) {
  const phoneCodes = new Map();
  return http.createServer({ requestTimeout: 8000, headersTimeout: 6000 }, async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    );
    try {
      const host = req.headers.host;
      if (!hosts.has(host) || !privatePeer(req.socket.remoteAddress))
        return json(res, 403, { error: 'Use the private bridge address.' });
      const path = (req.url || '').split('?')[0];
      if (path.startsWith('/api/')) {
        if (req.method === 'GET' && path === '/api/state')
          return json(res, 200, await bridge.snapshot());
        if (req.method !== 'POST' || !['/api/command', '/api/discover', '/api/devices', '/api/link', '/api/infrared'].includes(path))
          return json(res, 404, { error: 'Unknown endpoint.' });
        if (req.headers.origin !== 'http://' + host && req.headers.origin !== 'https://' + host)
          return json(res, 403, { error: 'Open Otoha to use the receiver.' });
        if (req.headers['content-type']?.split(';')[0] !== 'application/json')
          return json(res, 415, { error: 'A JSON command is required.' });
        const chunks = [];
        let size = 0;
        for await (const part of req) {
          size += part.length;
          if (size > (path === '/api/infrared' ? 4096 : 1024)) return json(res, 413, { error: 'Request too large.' });
          chunks.push(part);
        }
        let body;
        try {
          body = JSON.parse(Buffer.concat(chunks));
        } catch {
          return json(res, 400, { error: 'Invalid control request.' });
        }
        if (path === '/api/infrared') {
          if (!['search', 'select', 'manual', 'forget'].includes(body?.action) || typeof body.receiverId !== 'string')
            return json(res, 400, { error: 'Choose an infrared setup action for the linked receiver.' });
          const result = await bridge.infrared.update(body.receiverId, body.action, body.id, body.url);
          return json(res, 200, { ...result, receiverId: body.receiverId });
        }
        if (path === '/api/devices') return json(res, 200, { devices: await bridge.listDevices() });
        if (path === '/api/link') {
          if (typeof body?.id !== 'string') return json(res, 400, { error: 'Select a located device.' });
          return json(res, 200, await bridge.link(body.id));
        }
        if (path === '/api/discover') {
          await bridge.locate();
          return json(res, 200, await bridge.snapshot());
        }
        if (typeof body?.action !== 'string') return json(res, 400, { error: 'Choose a control.' });
        return json(res, 200, await bridge.run(body.action, body.value, body.targetId));
      }
      if (!['GET', 'HEAD'].includes(req.method)) return json(res, 405, { error: 'Unsupported method.' });
      if (path === '/phone-setup.png') {
        if (process.platform !== 'darwin' || !/\.local:\d+$/i.test(host))
          return json(res, 404, { error: 'Open the remote from Set Up Otoha on your Mac.' });
        if (!phoneCodes.has(host)) {
          const code = run('/usr/bin/osascript', ['-l', 'JavaScript', qrScript, 'http://' + host], { timeout: 5000 })
            .then(({ stdout }) => Buffer.from(stdout.trim(), 'base64'))
            .catch(error => { phoneCodes.delete(host); throw error; });
          phoneCodes.set(host, code);
        }
        const bytes = await phoneCodes.get(host);
        res.writeHead(200, { 'Content-Type': 'image/png', 'Content-Length': bytes.length });
        return res.end(req.method === 'HEAD' ? undefined : bytes);
      }
      const file = path === '/' ? '/index.html' : path;
      if (!/^\/(?:assets\/(?:hardware\/)?)?[a-z0-9][a-z0-9.-]*$/i.test(file))
        return json(res, 404, { error: 'Page unavailable.' });
      const type = types[file.split('.').pop()];
      if (!type) return json(res, 404, { error: 'File unavailable.' });
      const bytes = await readFile(fileURLToPath(new URL('.' + file, root))).catch(() => null);
      if (!bytes) return json(res, 404, { error: 'File unavailable.' });
      res.writeHead(200, {
        'Content-Type': type,
        'Cache-Control': 'no-cache',
        'Content-Length': bytes.length,
      });
      res.end(req.method === 'HEAD' ? undefined : bytes);
    } catch (error) {
      json(res, error.status || 503, { error: error.message || 'Receiver unavailable.' });
    }
  });
}
