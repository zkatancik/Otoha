import { TEMPLATES } from './templates';

export const DEVICE_TYPES = {
  avr: {
    name: 'AVR',
    template: 'avr',
    zones: ['Main Zone', 'Zone 2'],
    header:
      'POST AVR HTTP/1.1\r\nHost: :10025\r\nUser-Agent: Harman Kardon AVR Remote Controller /2.0',
  },
  bds: {
    name: 'BDS',
    template: 'bds',
    zones: ['Main Zone'],
    header:
      'POST HK_APP HTTP/1.1\r\nHost: :10025\r\nUser-Agent: Harman Kardon BDS Remote Controller/1.0',
  },
};

export function getDeviceType(key = 'avr') {
  return DEVICE_TYPES[key] ?? DEVICE_TYPES.avr;
}

export function generateRequest(actionName, zone, para = '', templateKey = 'avr') {
  const template = TEMPLATES[templateKey] ?? TEMPLATES.avr;
  return template
    .replace('{{ name }}', actionName)
    .replace('{{ zone }}', zone)
    .replace('{{ para }}', para ?? '')
    .trim();
}
