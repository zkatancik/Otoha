import { ACTIONS } from './actions';
import { generateRequest, getDeviceType } from './devices';

const RESPONSE_TIMEOUT_MS = 2000;

/**
 * Low-level HK stereo client. Transport is injected so the same protocol
 * layer can run in Node (tests) or React Native (TCP socket module).
 *
 * Usage:
 *   const zone = client.zone('Main Zone');
 *   await zone.volumeUp();
 *   await zone.selectSource('Disc');
 *
 * Commands are defined in `ACTIONS`. Only commands marked with `takesParam`
 * pass a parameter into the XML `<para>` field; all other commands send an
 * empty parameter.
 */
export class HKClient {
  constructor({ ip, port = 10025, deviceType = 'avr', transport }) {
    this.ip = ip;
    this.port = port;
    this.device = getDeviceType(deviceType);
    this.transport = transport;
  }

  /**
   * Wrap a generated XML body in the receiver-specific HTTP-like header.
   * This is sent directly over TCP; it is not using a normal fetch/XHR stack.
   */
  buildPayload(xmlBody) {
    return `${this.device.header}\r\nContent-Length: ${xmlBody.length}\r\n\r\n${xmlBody}`;
  }

  /**
   * Send one named action to one receiver zone.
   *
   * @param {string} actionKey Friendly key from `ACTIONS`, for example
   * `volumeUp`, `on`, or `selectSource`.
   * @param {string} zone Receiver zone, commonly `Main Zone`.
   * @param {string} param Optional parameter for parameterized commands.
   */
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

  /**
   * Send an arbitrary HK wire command for protocol exploration.
   *
   * This intentionally bypasses `ACTIONS` so we can test commands observed from
   * the native app or guessed from receiver menus. Use with care: unsupported
   * commands usually fail silently, and supported hidden commands may change
   * receiver settings immediately.
   *
   * @param {object} options
   * @param {string} options.name Wire command for `<name>`, for example
   * `harman-volume`.
   * @param {string} options.zone Receiver zone, commonly `Main Zone`.
   * @param {string} options.param Optional `<para>` value.
   * @param {boolean} options.hasResponse Whether to wait for a response.
   */
  async sendRawCommand({ name, zone, param = '', hasResponse = false }) {
    const commandName = name?.trim();
    if (!commandName) {
      throw new Error('Raw HK command name is required');
    }

    const xml = generateRequest(commandName, zone, param, this.device.template);
    const payload = this.buildPayload(xml);

    await this.transport.send(this.ip, this.port, payload);

    if (hasResponse) {
      return this.transport.read(RESPONSE_TIMEOUT_MS);
    }
  }

  /**
   * Return a dynamic zone proxy whose methods match keys in `ACTIONS`.
   * Unknown method names intentionally resolve to undefined.
   */
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
