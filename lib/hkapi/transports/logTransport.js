/**
 * Dev transport — logs payloads instead of opening a socket.
 * Swap for a TCP transport once react-native-tcp-socket is wired up.
 */
export function createLogTransport() {
  return {
    async send(ip, port, payload) {
      console.log(`[HKAPI] → ${ip}:${port}`);
      console.log(payload);
    },
    async read() {
      return '<mock-response />';
    },
  };
}
