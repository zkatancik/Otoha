import dns from 'node:dns';
import http from 'node:http';
import https from 'node:https';
import { localIPv4 } from './device.js';

export function manualBlaster(value) {
  const invalid = () => Object.assign(new Error(
    'Enter a local HTTP or HTTPS webhook URL with a private IPv4 address or a .local hostname. Leave out usernames, passwords and fragments.'
  ), { status: 400 });
  if (typeof value !== 'string') throw invalid();
  const text = value.trim();
  if (text.length > 2048 || !/^https?:\/\//i.test(text) || /[\s\\#\x00-\x1f\x7f]/.test(text)) throw invalid();
  let url;
  try { url = new URL(text); } catch { throw invalid(); }
  if (url.href.length > 2048 || url.username || url.password || url.port === '0' ||
      !(localIPv4(url.hostname) || url.hostname.endsWith('.local'))) throw invalid();
  return { kind: 'webhook', model: 'Custom IR blaster', url: url.href };
}

// Resolve at connection time so the socket uses the private address we checked.
function lookupLocal(host, options, callback) {
  dns.lookup(host, { family: 4 }, (error, address) => {
    if (error || !localIPv4(address)) return callback(new Error('Local webhook unavailable.'));
    if (options.all) return callback(null, [{ address, family: 4 }]);
    callback(null, address, 4);
  });
}

export function sendWebhook(device) {
  const url = new URL(manualBlaster(device.url).url);
  const transport = url.protocol === 'https:' ? https : http;
  return new Promise((resolve, reject) => {
    const request = transport.request(url, {
      method: 'POST', family: 4, lookup: lookupLocal, agent: false, signal: AbortSignal.timeout(8000),
    }, response => {
      // Only the acceptance status matters. A redirect must not trigger another request.
      response.destroy();
      if (response.statusCode >= 200 && response.statusCode < 300) resolve();
      else reject(new Error('The webhook did not accept Power on. Check its POST trigger and saved command.'));
    });
    request.on('error', () => reject(new Error('Could not reach the IR webhook. Check its local address and that the controller is on.')));
    request.end();
  });
}
