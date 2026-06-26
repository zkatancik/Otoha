import TcpSocket from 'react-native-tcp-socket';

const POLL_INTERVAL_MS = 500;
const CONNECT_TIMEOUT_MS = 2000;

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function toMessage(error, ip, port) {
  const detail = error?.message ? ` ${error.message}` : '';
  return `Cannot reach stereo at ${ip}:${port}. Check Wi-Fi and IP.${detail}`;
}

export function createTcpTransport() {
  let socket = null;
  let endpoint = null;
  let readBuffer = '';
  let connecting = null;
  let lastError = null;

  function resetSocket() {
    if (socket) {
      socket.removeAllListeners();
      socket.destroy();
    }

    socket = null;
    endpoint = null;
    connecting = null;
  }

  function attachSocket(nextSocket, ip, port) {
    socket = nextSocket;
    endpoint = `${ip}:${port}`;
    lastError = null;

    socket.on('data', (data) => {
      readBuffer += data?.toString ? data.toString() : String(data);
    });

    socket.on('error', (error) => {
      lastError = error;
      resetSocket();
    });

    socket.on('close', () => {
      resetSocket();
    });
  }

  function connect(ip, port) {
    const nextEndpoint = `${ip}:${port}`;
    if (socket && endpoint === nextEndpoint) {
      return Promise.resolve(socket);
    }

    if (connecting && endpoint === nextEndpoint) {
      return connecting;
    }

    resetSocket();
    endpoint = nextEndpoint;

    connecting = new Promise((resolve, reject) => {
      let settled = false;
      const timeout = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        resetSocket();
        reject(new Error(toMessage(new Error('Connection timed out.'), ip, port)));
      }, CONNECT_TIMEOUT_MS);

      const nextSocket = TcpSocket.createConnection({ host: ip, port }, () => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeout);
        attachSocket(nextSocket, ip, port);
        resolve(nextSocket);
      });

      nextSocket.once('error', (error) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeout);
        resetSocket();
        reject(new Error(toMessage(error, ip, port)));
      });
    });

    return connecting;
  }

  return {
    async send(ip, port, payload) {
      const activeSocket = await connect(ip, port);

      // HKAPI clears up to 4096 bytes from the socket before every request.
      readBuffer = '';

      await new Promise((resolve, reject) => {
        activeSocket.write(payload, (error) => {
          if (error) {
            resetSocket();
            reject(new Error(toMessage(error, ip, port)));
            return;
          }

          resolve();
        });
      });
    },

    async read(timeoutMs) {
      const deadline = Date.now() + timeoutMs;

      while (!readBuffer && Date.now() < deadline) {
        if (lastError) {
          throw lastError;
        }
        await delay(POLL_INTERVAL_MS);
      }

      if (!readBuffer) {
        throw new Error(`Exceeded timeout of ${timeoutMs}ms while waiting for response.`);
      }

      const response = readBuffer;
      readBuffer = '';
      const xmlStart = response.indexOf('<?xml');

      return xmlStart >= 0 ? `${response.slice(xmlStart)}>` : response;
    },

    close() {
      resetSocket();
      readBuffer = '';
    },
  };
}
