import { HKClient, createLogTransport, createTcpTransport } from '../lib/hkapi';
import { loadStereoConfig } from './stereoConfig';

const USE_LOG_TRANSPORT = false;

let client = null;
let activeZone = null;
let activeTransport = null;
let activeConfigKey = null;

function getConfigKey(config) {
  return [config.ip, config.port, config.deviceType, config.zone].join('|');
}

function createTransport() {
  if (__DEV__ && USE_LOG_TRANSPORT) {
    return createLogTransport();
  }

  return createTcpTransport();
}

async function getClient() {
  const config = await loadStereoConfig();
  if (!config.ip) {
    throw new Error('Stereo IP is not configured');
  }

  const nextConfigKey = getConfigKey(config);
  if (!client || activeConfigKey !== nextConfigKey) {
    activeTransport?.close?.();
    activeTransport = createTransport();
    client = new HKClient({
      ip: config.ip,
      port: config.port,
      deviceType: config.deviceType,
      transport: activeTransport,
    });
    activeZone = client.zone(config.zone);
    activeConfigKey = nextConfigKey;
  }

  return { client, zone: activeZone, config };
}

export async function runStereoAction(action, param) {
  const { zone } = await getClient();
  if (typeof zone[action] !== 'function') {
    throw new Error(`Unknown stereo action: ${action}`);
  }

  return zone[action](param);
}

export { loadStereoConfig, saveStereoConfig } from './stereoConfig';
