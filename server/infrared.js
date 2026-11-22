import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { localIPv4 } from './device.js';
import { manualBlaster, sendWebhook } from './ir-webhook.js';

const run = promisify(execFile);
const scripts = fileURLToPath(new URL('../scripts/', import.meta.url));
const key = device => device.kind + '-' + device.mac;
const conflict = message => Object.assign(new Error(message), { status: 409 });
const bonjourKinds = new Set(['tasmota', 'irkit', 'remo']);

function valid(device) {
  return device && (bonjourKinds.has(device.kind) || ['itach', 'broadlink'].includes(device.kind)) &&
    (!bonjourKinds.has(device.kind) || (Number.isInteger(device.port) && device.port >= 1 && device.port <= 65535)) &&
    localIPv4(device.host) &&
    typeof device.mac === 'string' && /^[a-f0-9]{12}$/.test(device.mac) &&
    typeof device.model === 'string' && device.model.length > 0 && device.model.length <= 100;
}

async function driver(kind, operation, args) {
  const command = kind === 'itach' ? ['python3', '-B', join(scripts, 'itach-ir.py')] :
    ['/bin/sh', join(scripts, 'run-ir-driver.sh'), kind];
  try {
    const { stdout } = await run(command[0], [...command.slice(1), operation, ...args], {
      timeout: operation === 'discover' ? 90000 : 6000, maxBuffer: 128 * 1024,
    });
    if (operation === 'discover') return JSON.parse(stdout).filter(valid);
  } catch (error) {
    const detail = error.stderr?.trim();
    if (error.code === 1 && detail && !detail.includes('\n') && detail.length < 240)
      throw new Error(detail);
    if (operation === 'discover' && kind === 'broadlink')
      throw new Error('BroadLink support could not start. Check Python 3 and internet access on the bridge.');
    if (operation === 'discover' && kind === 'bonjour')
      throw new Error('Bonjour discovery could not start. Check Python 3.9 or newer and internet access on the bridge.');
    throw new Error('Check Python 3, local network access and the blaster connection on the bridge.');
  }
}

export const sendSavedBroadlink = directory => driver('broadlink', 'send', ['--directory', directory]);

function operate(device, operation) {
  const args = ['--address', device.host, '--mac', device.mac];
  if (bonjourKinds.has(device.kind))
    return driver('bonjour', operation, [...args, '--kind', device.kind, '--port', String(device.port)]);
  return driver(device.kind, operation, args);
}

export const localBlasters = {
  async discover() {
    const interfaces = Object.values(networkInterfaces()).flat().filter(n =>
      n && !n.internal && n.cidr && localIPv4(n.address));
    if (!interfaces.length) throw new Error('Connect the bridge to your home network and search again.');
    const args = interfaces.flatMap(n => ['--interface', n.cidr]);
    const results = await Promise.allSettled(['itach', 'broadlink', 'bonjour'].map(kind => driver(kind, 'discover', args)));
    const devices = results.flatMap(result => result.status === 'fulfilled' ? result.value : []);
    const failure = results.find(result => result.status === 'rejected');
    if (!devices.length && failure) throw failure.reason;
    return devices;
  },
  check: device => operate(device, 'check'),
  send: device => device.kind === 'webhook' ? sendWebhook(device) : operate(device, 'send'),
};

// Only an explicit setup request starts a job. Polling reads its progress or the saved link.
export class InfraredSetup {
  constructor(directory, drivers, checkReceiver, invalidate) {
    this.directory = directory;
    this.drivers = drivers;
    this.checkReceiver = checkReceiver;
    this.invalidate = invalidate;
    this.updates = Promise.resolve();
  }

  file(receiverId) {
    const hash = createHash('sha256').update(receiverId).digest('hex');
    return join(this.directory, 'ir-blaster-' + hash + '.json');
  }

  async saved(receiverId) {
    try {
      const device = JSON.parse(await readFile(this.file(receiverId), 'utf8'));
      if (device?.kind === 'webhook') return manualBlaster(device.url);
      if (!valid(device)) throw new Error('Invalid saved blaster.');
      return device;
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw new Error('The bridge could not read the saved IR blaster.');
    }
  }

  async status(receiverId) {
    let device;
    try {
      device = await this.saved(receiverId);
    } catch {
      return { phase: 'broken', message: 'The saved blaster could not be read. Forget it and run setup again.' };
    }
    if (device) return { phase: 'linked', label: device.model };
    return this.receiverId === receiverId ? this.progress : { phase: 'idle' };
  }

  report(phase, fields = {}) {
    this.progress = { phase, ...fields };
    this.invalidate();
    return this.progress;
  }

  async link(receiverId, device) {
    // Posting to a webhook would send power. Only the Power on control calls it.
    if (device.kind !== 'webhook') await this.drivers.check(device);
    await this.checkReceiver(receiverId);
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    const file = this.file(receiverId);
    const temp = file + '.' + randomUUID();
    try {
      await writeFile(temp, JSON.stringify(device), { mode: 0o600, flag: 'wx' });
      await rename(temp, file);
    } finally {
      await rm(temp, { force: true });
    }
    this.receiverId = receiverId;
    return this.report('linked', { label: device.model });
  }

  async discover(receiverId) {
    const devices = await this.drivers.discover();
    await this.checkReceiver(receiverId);
    this.candidates = new Map(devices.filter(valid).map(device => [key(device), device]));
    if (!this.candidates.size)
      throw new Error('No compatible blaster answered. Check power, local discovery and the IR output, then search again.');
    if (this.candidates.size === 1) {
      this.report('linking');
      return this.link(receiverId, this.candidates.values().next().value);
    }
    return this.report('choose', { devices: Array.from(this.candidates, ([id, device]) =>
      ({ id, label: device.model, host: device.host })) });
  }

  update(receiverId, action, id, url) {
    const result = this.updates.then(() => this.beginUpdate(receiverId, action, id, url));
    this.updates = result.catch(() => {});
    return result;
  }

  async beginUpdate(receiverId, action, id, url) {
    await this.checkReceiver(receiverId);
    const state = await this.status(receiverId);
    if (this.job) {
      if (this.receiverId === receiverId && action === 'search') return this.progress;
      throw conflict('Blaster setup is in progress. Try again when it finishes.');
    }
    if (action === 'forget') {
      if (!['linked', 'broken'].includes(state.phase)) throw conflict('There is no linked blaster to forget.');
      await rm(this.file(receiverId), { force: true });
      this.receiverId = receiverId;
      return this.report('idle');
    }
    if (action === 'manual') {
      const device = manualBlaster(url);
      if (state.phase === 'linked') {
        if ((await this.saved(receiverId))?.url === device.url) return state;
        throw conflict('Forget the linked blaster before adding another one.');
      }
      if (state.phase === 'broken') throw conflict(state.message);
      return this.link(receiverId, device);
    }
    if (state.phase === 'linked') return state;
    const candidate = action === 'select' && state.phase === 'choose' && this.candidates?.get(id);
    if (action !== 'search' && !candidate) throw conflict('Choose a blaster from the current search.');
    this.receiverId = receiverId;
    const initial = this.report(candidate ? 'linking' : 'searching');
    this.job = (candidate ? this.link(receiverId, candidate) : this.discover(receiverId))
      .catch(error => this.report('error', { message: error.message }))
      .finally(() => { this.job = null; });
    return initial;
  }
}
