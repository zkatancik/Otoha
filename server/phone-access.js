import { randomBytes, randomInt, createHash, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export const defaultDirectory = process.env.OTOHA_DATA || join(homedir(), '.config', 'otoha');
const digest = (value) => createHash('sha256').update(value).digest('hex');
function read(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
}
function save(path, data) {
  const tmp = path + '.' + randomBytes(6).toString('hex');
  writeFileSync(tmp, JSON.stringify(data), { mode: 0o600, flag: 'wx' });
  renameSync(tmp, path);
}

// The private CLI issues codes. Only the gateway consumes them, synchronously.
export class PhoneAccess {
  constructor(directory = defaultDirectory) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.codeFile = join(directory, 'iphone-pairing.json');
    this.keysFile = join(directory, 'iphone-keys.json');
  }
  issue() {
    const code = String(randomInt(0, 100000000)).padStart(8, '0');
    save(this.codeFile, { hash: digest(code), until: Date.now() + 600000, attempts: 5 });
    return code;
  }
  pair(code) {
    const offer = read(this.codeFile, null);
    if (!offer || offer.until < Date.now() || offer.attempts < 1) return null;
    const valid =
      typeof code === 'string' &&
      /^\d{8}$/.test(code) &&
      timingSafeEqual(Buffer.from(digest(code), 'hex'), Buffer.from(offer.hash, 'hex'));
    save(this.codeFile, valid ? null : { ...offer, attempts: offer.attempts - 1 });
    if (!valid) return null;
    const key = randomBytes(32).toString('base64url');
    const keys = read(this.keysFile, []);
    save(this.keysFile, [...keys, digest(key)]);
    return key;
  }
  revoke(header) {
    const removed = digest(header.slice(7));
    save(
      this.keysFile,
      read(this.keysFile, []).filter((key) => key !== removed),
    );
  }
  accepts(header) {
    const key = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(header || '')?.[1];
    if (!key) return false;
    const hash = Buffer.from(digest(key), 'hex');
    return read(this.keysFile, []).some((stored) => timingSafeEqual(hash, Buffer.from(stored, 'hex')));
  }
}
