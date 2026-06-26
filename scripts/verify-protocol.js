const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');

function runModule(relativePath, transform, globals = {}) {
  const filePath = path.join(projectRoot, relativePath);
  const source = fs.readFileSync(filePath, 'utf8');
  const exports = {};
  const context = vm.createContext({ exports, ...globals });
  vm.runInContext(transform(source), context, { filename: filePath });
  return exports;
}

const { ACTIONS } = runModule(
  'lib/hkapi/actions.js',
  (source) =>
    source
      .replace('export const ACTIONS =', 'exports.ACTIONS =')
      .replace('export const KNOWN_SOURCE_LABELS =', 'exports.KNOWN_SOURCE_LABELS ='),
);

const { TEMPLATES } = runModule(
  'lib/hkapi/templates.js',
  (source) =>
    source
      .replace('export const AVR_TEMPLATE =', 'const AVR_TEMPLATE =')
      .replace('export const BDS_TEMPLATE =', 'const BDS_TEMPLATE =')
      .replace('export const TEMPLATES =', 'exports.TEMPLATES ='),
);

const { generateRequest, getDeviceType } = runModule(
  'lib/hkapi/devices.js',
  (source) =>
    source
      .replace("import { TEMPLATES } from './templates';\n\n", '')
      .replace('export const DEVICE_TYPES =', 'const DEVICE_TYPES = exports.DEVICE_TYPES =')
      .replace('export function getDeviceType', 'exports.getDeviceType = function')
      .replace('export function generateRequest', 'exports.generateRequest = function'),
  { TEMPLATES },
);

const { HKClient } = runModule(
  'lib/hkapi/client.js',
  (source) =>
    source
      .replace("import { ACTIONS } from './actions';\n", '')
      .replace("import { generateRequest, getDeviceType } from './devices';\n", '')
      .replace('export class HKClient', 'exports.HKClient = class HKClient'),
  { ACTIONS, generateRequest, getDeviceType },
);

const fixtures = [
  { action: 'volumeUp', zone: 'Main Zone' },
  { action: 'volumeDown', zone: 'Main Zone' },
  { action: 'selectSource', zone: 'Main Zone', param: 'Disc' },
  { action: 'on', zone: 'Main Zone' },
  { action: 'heartAlive', zone: 'Main Zone' },
  { rawName: 'harman-volume', zone: 'Main Zone', param: 'Low' },
];

const client = new HKClient({
  ip: '192.168.1.242',
  deviceType: 'avr',
  transport: {
    async send() {},
    async read() {},
  },
});

const output = fixtures.map(({ action, rawName, zone, param }) => {
  if (rawName) {
    const body = generateRequest(rawName, zone, param ?? '', client.device.template);

    return {
      action: 'raw',
      rawName,
      zone,
      param: param ?? null,
      body,
      payload: client.buildPayload(body),
    };
  }

  const actionConfig = ACTIONS[action];
  const body = generateRequest(
    actionConfig.name,
    zone,
    actionConfig.takesParam ? param : '',
    client.device.template,
  );

  return {
    action,
    zone,
    param: param ?? null,
    body,
    payload: client.buildPayload(body),
  };
});

console.log(JSON.stringify(output, null, 4));
