import { randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir, rename, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { discover, identify, transmit, frame, rendering, textOf, localIPv4, uniqueDevices } from './device.js';
import { profiles, deviceSources, matchModel } from './profiles.js';
import { InfraredSetup, localBlasters, sendSavedBroadlink } from './infrared.js';
import { harmanModes } from '../public/catalog.js';

const problem = (status, message) => Object.assign(new Error(message), { status });
// Older caches can lack a UDN. Keep their offline identity usable until discovery returns a UDN.
const deviceId = device => device && (device.id || 'legacy-ip:' + device.host);
const summary = device => {
  const { host, model, name, profile } = device;
  return { id: deviceId(device), host, model, name, profile };
};

const messages = {
  harman: 'Mode press sent. Check the receiver display.',
  wake: 'Network wake requested.',
  standby: 'Standby requested.',
  mute: 'Mute toggle sent.',
  sleep: 'Sleep timer press sent. Check the receiver display.',
};

export class Bridge {
  constructor({ address, directory, wakeUrl, send = transmit, renderer = rendering, sendBroadlink = sendSavedBroadlink, scan = discover, describe = identify, blasters = localBlasters }) {
    this.directory = directory;
    this.scan = scan;
    this.describe = describe;
    this.candidates = new Map();
    this.send = send;
    this.renderer = renderer;
    this.sendBroadlink = sendBroadlink;
    this.infrared = new InfraredSetup(directory, blasters, async id => {
      const device = this.device || this.saved;
      if (this.switching || !id || device?.id !== id || device.model !== 'HK 3770')
        throw problem(409, 'Link the HK 3770 you want to wake, then open infrared setup again.');
      if (id === this.irOwner && await this.infraredWakeURL())
        throw problem(409, 'This receiver already uses infrared wake configured on the bridge.');
    }, () => this.invalidate());
    if (address && !localIPv4(address)) throw new Error('HK_HOST must be a private LAN IPv4 address.');
    this.address = address;
    this.wakeUrl = wakeUrl;
    this.device = null;
    this.lastSource = null;
    this.lastSeen = null;
    this.trackedMode = null;
    this.lastSearch = 0;
    this.cached = null;
    this.generation = 0;
    this.queued = 0;
    this.tail = Promise.resolve();
  }

  async infraredWakeURL() {
    if (this.wakeUrl) return this.wakeUrl;
    try {
      return (await readFile(join(this.directory, 'ir-wake-url'), 'utf8')).trim() || null;
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }
  }

  async init() {
    try {
      const saved = JSON.parse(await readFile(join(this.directory, 'receiver.json'), 'utf8'));
      const legacy = !saved.profile && !saved.model;
      const model = legacy ? matchModel('HK 3770') : matchModel(saved.model);
      if (localIPv4(saved.host) && model && (legacy || saved.id)) {
        this.saved = { ...saved, ...model, name: saved.name || model.model };
        this.irOwner = saved.irOwner ?? (legacy ? saved.id : null);
      }
    } catch {}
    if (this.saved) await this.locate();
  }

  async listDevices() {
    if (!this.scanning) {
      const hints = this.address ? ['dd.xml', 'description.xml'].map(path =>
        this.describe('http://' + this.address + ':8080/' + path).catch(() => null)) : [];
      this.scanning = Promise.all([this.scan(), ...hints]).then(([devices, ...hinted]) => {
        const found = uniqueDevices([...devices, ...hinted]);
        this.candidates = new Map(found.map(device => [device.id, device]));
        this.scannedAt = Date.now();
        return found;
      }).finally(() => { this.scanning = null; });
    }
    return (await this.scanning).map(summary);
  }

  async resolve(expected) {
    const matches = device => device?.model === expected.model &&
      (expected.id ? device.id === expected.id : device.host === expected.host);
    if (!expected.advertised) {
      const location = expected.location || 'http://' + expected.host + ':8080/dd.xml';
      const current = await this.describe(location).catch(() => null);
      if (matches(current)) return current;
    }
    await this.listDevices();
    return [...this.candidates.values()].find(matches);
  }

  async persist(device, irOwner) {
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    const file = join(this.directory, 'receiver.json');
    const temporary = file + '.' + randomUUID();
    try {
      await writeFile(temporary, JSON.stringify({ ...device, irOwner }), { mode: 0o600, flag: 'wx' });
      await rename(temporary, file);
    } finally {
      await rm(temporary, { force: true });
    }
    this.irOwner = irOwner;
  }

  locate() {
    if (!this.saved || this.switching) return Promise.resolve(this.device);
    if (!this.search) {
      this.lastSearch = Date.now();
      this.search = (async () => {
        const device = await this.resolve(this.saved);
        if (!device) this.device = null;
        else {
          await this.persist(device, this.irOwner || (device.model === 'HK 3770' ? device.id : null));
          this.device = this.saved = device;
        }
        this.invalidate();
        return device;
      })().finally(() => { this.search = null; });
    }
    return this.search;
  }

  async link(id) {
    const candidate = this.candidates.get(id);
    if (!candidate || Date.now() - this.scannedAt > 120000)
      throw problem(409, 'Locate devices again and select a current result.');
    if (this.switching || this.queued) throw problem(409, 'The bridge is busy. Try linking again.');
    this.switching = true;
    try {
      await this.search;
      const device = await this.resolve(candidate);
      if (!device) throw problem(409, 'This device moved or disappeared. Locate it again.');
      const status = await this.probe(device);
      if (!status.online) throw problem(503, 'The device did not answer its remote connection. Turn it on and try again.');
      const irOwner = this.irOwner || (device.model === 'HK 3770' ? device.id : null);
      const state = await this.state(device, status, irOwner);
      await this.persist(device, irOwner);
      this.device = this.saved = device;
      this.lastSource = null;
      this.trackedMode = null;
      this.lastSeen = Date.now();
      this.lastSearch = this.lastSeen;
      this.invalidate();
      this.cached = { ...state, at: this.lastSeen, lastSeen: this.lastSeen, lastSource: null, trackedMode: null };
      return this.cached;
    } finally {
      this.switching = false;
    }
  }

  invalidate() {
    this.cached = null;
    this.generation++;
  }

  async snapshot() {
    if (this.cached && Date.now() - this.cached.at < 2200) return this.cached;
    if (!this.reading) {
      const epoch = this.generation;
      this.reading = this.read()
        .then((state) => {
          if (epoch === this.generation) this.cached = state;
          return state;
        })
        .finally(() => {
          this.reading = null;
        });
    }
    return this.reading;
  }

  async probe(device) {
    if (!device) return { online: false, networkVolume: null, networkMute: null };
    const heartbeat = frame('heart-alive', '', '', device.profile);
    const [alive, volume, mute] = await Promise.allSettled([
      this.send(device.host, [heartbeat], true),
      device.control && this.renderer(device, 'GetVolume'),
      device.control && this.renderer(device, 'GetMute'),
    ]);
    const value = volume.value && textOf(volume.value, 'CurrentVolume');
    const networkVolume = /^\d{1,3}$/.test(value) && Number(value) <= 100 ? Number(value) : null;
    const flag = mute.value && textOf(mute.value, 'CurrentMute');
    const networkMute = flag === '0' || flag === '1' ? flag === '1' : null;
    // HK 3770 sometimes closes silently. The upstream AVR 170 also omits the heartbeat.
    const silent170 = /^AVR 170(?:0|\/1700|\/230C)?$/.test(device.model);
    const online = alive.status === 'fulfilled' || (alive.reason?.frameSent === true &&
      alive.reason.receivedData !== true && ((['stereo', 'mm'].includes(device.profile) &&
        (networkVolume !== null || networkMute !== null)) || silent170));
    return { online, networkVolume, networkMute };
  }

  async read() {
    if (!this.device && this.saved && Date.now() - this.lastSearch > 30000) {
      // Keep the bridge's state endpoint responsive while an offline device is rediscovered.
      this.locate().catch(error => console.warn('Receiver rediscovery failed:', error.message));
    }
    const device = this.device;
    const status = await this.probe(device);
    if (device !== this.device) return this.state(this.saved, await this.probe(this.device));
    if (status.online) this.lastSeen = Date.now();
    else if (device) {
      this.lastSource = this.trackedMode = null;
      this.device = null;
    }
    return this.state(this.saved || device, status);
  }

  async state(device, status, irOwner = this.irOwner) {
    const legacyWake = !!device?.id && device.id === irOwner && Boolean(await this.infraredWakeURL());
    let infrared;
    if (device?.id && device.model === 'HK 3770') {
      const setup = legacyWake ? { phase: 'external' } : await this.infrared.status(device.id);
      infrared = { ...setup, receiverId: device.id };
    }
    return {
      ...status, at: Date.now(), lastSeen: this.lastSeen, host: device?.host || null,
      linked: !!device, device: device ? summary(device) : null,
      actions: device ? Object.keys(profiles[device.profile].keys)
        .filter(key => key !== 'harman' || device.model === 'HK 3770') : [],
      sources: device ? deviceSources(device).map(({ id, name, detail }) => ({ id, name, detail })) : [],
      lastSource: this.lastSource, trackedMode: this.trackedMode,
      infrared, irWake: legacyWake || infrared?.phase === 'linked',
    };
  }

  run(action, value, targetId) {
    const device = this.device || this.saved;
    if (this.switching || (targetId !== undefined && targetId !== deviceId(device)))
      throw problem(409, 'The linked device changed. Refresh the remote and try again.');
    const profile = device?.profile || 'stereo';
    const keys = profiles[profile].keys;
    const source = action === 'source' && device && deviceSources(device).find(i => i.id === value);
    const setVolume = action === 'network-volume' && device?.control && Number.isInteger(value) && value >= 0 && value <= 100;
    const speakerLevel = action === 'speaker-volume' && profile === 'mm' && ['number', 'string'].includes(typeof value) && /^(?:100|[1-9]?\d)$/.test(String(value));
    const supportsMode = device?.model === 'HK 3770';
    const modeControl = supportsMode && ['sync-mode', 'set-mode'].includes(action) && harmanModes.includes(value);
    if ((action === 'harman' && device && !supportsMode) || (!Object.hasOwn(keys, action) && !source && !setVolume && !modeControl && !speakerLevel))
      throw problem(400, 'This control is unavailable for the linked device.');
    if (this.queued >= 4)
      throw Object.assign(new Error('The receiver is busy. Try again.'), { status: 429 });
    this.queued++;
    const expires = Date.now() + 2200;
    const result = this.tail.then(async () => {
      if (Date.now() > expires) throw new Error('Command expired. Try again.');
      const wakeURL = device?.id && device.id === this.irOwner && action === 'wake' && (await this.infraredWakeURL());
      const blaster = !wakeURL && action === 'wake' && device?.model === 'HK 3770' && device.id &&
        await this.infrared.saved(device.id);
      if (wakeURL || blaster) {
        if (blaster) {
          await this.infrared.drivers.send(blaster);
        } else if (wakeURL === 'broadlink:power-on') {
          await this.sendBroadlink(this.directory);
        } else {
          const response = await fetch(wakeURL, {
            method: 'POST',
            signal: AbortSignal.timeout(3500),
            redirect: 'error',
          });
          if (!response.ok) throw new Error('The infrared bridge did not accept the wake request.');
        }
        this.lastSource = null;
        this.trackedMode = null;
        return { message: 'Infrared wake requested.', lastSource: null, trackedMode: null };
      }
      if (!this.device && action === 'wake' && this.saved) await this.locate();
      const host = this.device?.host;
      if (!host) throw new Error('Receiver unavailable. Turn it on, then find it in Receiver settings.');
      if (action === 'sync-mode') {
        if (!(await this.snapshot()).online)
          throw new Error('Connect to the receiver before syncing its mode.');
        this.trackedMode = value;
        return { message: 'Tracking ' + value + ' from the receiver display.', trackedMode: value };
      }
      if (action === 'set-mode') {
        if (!this.trackedMode)
          throw Object.assign(new Error('Sync the front-panel mode first.'), { status: 409 });
        const count =
          (harmanModes.indexOf(value) - harmanModes.indexOf(this.trackedMode) + harmanModes.length) %
          harmanModes.length;
        try {
          for (let step = 0; step < count; step++) {
            if (step) await new Promise((resolve) => setTimeout(resolve, 340));
            await this.send(host, [frame(keys.harman)]);
          }
        } catch {
          this.trackedMode = null;
          throw new Error('The mode sequence was interrupted. Sync with the front display.');
        }
        this.trackedMode = value;
        return { message: value + ' tracked. Resync if the handset changes it.', trackedMode: value };
      }
      if (setVolume) {
        await this.renderer(this.device, 'SetVolume', { DesiredVolume: value });
        return { message: 'Network playback level sent.' };
      }
      const name = source ? 'source-selection' : speakerLevel ? 'set_system_volume' : keys[action];
      const parameter = source ? source.wire : speakerLevel ? value : '';
      const packets = [frame(name, parameter, source?.zone, profile)];
      if (profile === 'stereo' && source?.id === 'usb') packets.push(frame('source-selection', 'iPod'));
      try {
        await this.send(host, packets);
      } catch {
        if (action === 'harman') this.trackedMode = null;
        throw new Error(
          action === 'wake'
            ? 'The network port is asleep. Use the receiver’s On button or an infrared bridge.'
            : 'Could not reach the linked device. Check its power and network connection.',
        );
      }
      if (source) this.lastSource = source.id;
      if (action === 'standby' || action === 'wake') {
        this.lastSource = null;
        this.trackedMode = null;
      }
      if (action === 'harman' && this.trackedMode)
        this.trackedMode = harmanModes[(harmanModes.indexOf(this.trackedMode) + 1) % harmanModes.length];
      return {
        message: source ? source.name + ' requested.' : messages[action] || 'Command sent.',
        lastSource: this.lastSource,
        trackedMode: this.trackedMode,
      };
    });
    this.tail = result
      .catch(() => {})
      .finally(() => {
        this.queued--;
        this.invalidate();
      });
    return result;
  }
}
