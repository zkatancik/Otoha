import * as Network from 'expo-network';
import TcpSocket from 'react-native-tcp-socket';

const HK_PORT = 10025;
const CONNECT_TIMEOUT_MS = 450;
const CONCURRENCY = 32;

function getSubnetPrefix(ipAddress) {
  const parts = ipAddress?.split('.');
  if (parts?.length !== 4) {
    throw new Error('Could not determine the local Wi-Fi subnet.');
  }

  return parts.slice(0, 3).join('.');
}

function probePort(ip, port = HK_PORT, timeoutMs = CONNECT_TIMEOUT_MS) {
  return new Promise((resolve) => {
    let socket = null;
    let settled = false;

    const finish = (isOpen) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      socket?.removeAllListeners();
      socket?.destroy();
      resolve(isOpen);
    };

    const timer = setTimeout(() => finish(false), timeoutMs);

    try {
      socket = TcpSocket.createConnection({ host: ip, port }, () => finish(true));
      socket.once('error', () => finish(false));
      socket.once('close', () => finish(false));
    } catch (_error) {
      finish(false);
    }
  });
}

async function runLimited(items, limit, worker) {
  const results = [];
  let nextIndex = 0;

  async function runNext() {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      const result = await worker(items[currentIndex], currentIndex);
      if (result) {
        results.push(result);
      }
    }
  }

  await Promise.all(Array.from({ length: limit }, runNext));
  return results;
}

export async function discoverStereos({ onProgress } = {}) {
  const ipAddress = await Network.getIpAddressAsync();
  const subnetPrefix = getSubnetPrefix(ipAddress);
  const candidates = Array.from({ length: 254 }, (_value, index) => `${subnetPrefix}.${index + 1}`);
  let scanned = 0;

  const devices = await runLimited(candidates, CONCURRENCY, async (candidateIp) => {
    const isOpen = await probePort(candidateIp);
    scanned += 1;
    onProgress?.({ scanned, total: candidates.length, subnetPrefix });

    if (!isOpen) {
      return null;
    }

    return {
      id: candidateIp,
      name: 'Harman Kardon candidate',
      ip: candidateIp,
      port: HK_PORT,
    };
  });

  return {
    localIp: ipAddress,
    subnetPrefix,
    devices: devices.sort((a, b) => a.ip.localeCompare(b.ip, undefined, { numeric: true })),
  };
}
