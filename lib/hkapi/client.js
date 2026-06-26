import { ACTIONS } from './actions';
import { generateRequest, getDeviceType } from './devices';

const RESPONSE_TIMEOUT_MS = 2000;

/**
 * Low-level HK stereo client. Transport is injected so the same protocol
 * layer can run in Node (tests) or React Native (TCP socket module).
 */
export class HKClient {
  constructor({ ip, port = 10025, deviceType = 'avr', transport }) {
    this.ip = ip;
    this.port = port;
    this.device = getDeviceType(deviceType);
    this.transport = transport;
  }

  buildPayload(xmlBody) {
    return `${this.device.header}\r\nContent-Length: ${xmlBody.length}\r\n\r\n${xmlBody}`;
  }

  async sendAction(actionKey, zone, param) {
    const action = ACTIONS[actionKey];
    if (!action) {
      throw new Error(`Unknown action: ${actionKey}`);
    }

    const xml = generateRequest(
      action.name,
      zone,
      action.takesParam ? param : '',
      this.device.template,
    );
    const payload = this.buildPayload(xml);

    await this.transport.send(this.ip, this.port, payload);

    if (action.hasResponse) {
      return this.transport.read(RESPONSE_TIMEOUT_MS);
    }
  }

  zone(name) {
    const client = this;
    return new Proxy(
      {},
      {
        get(_target, prop) {
          if (typeof prop !== 'string' || !(prop in ACTIONS)) {
            return undefined;
          }
          return (param) => client.sendAction(prop, name, param);
        },
      },
    );
  }
}
