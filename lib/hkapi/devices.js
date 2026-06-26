import { TEMPLATES } from './templates';

/**
 * Device profiles define the envelope around the same command body.
 *
 * AVR and BDS receivers share the `<common><control>` payload shape, but they
 * use different root XML tags and different HTTP-like POST headers. The `zones`
 * arrays are the known upstream defaults; the receiver may still reject or
 * ignore a zone depending on model/configuration.
 */
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

/**
 * Resolve a configured device type. Unknown values fall back to AVR because it
 * is the most common HKAPI target and matches the upstream PHP default.
 */
export function getDeviceType(key = 'avr') {
  return DEVICE_TYPES[key] ?? DEVICE_TYPES.avr;
}

/**
 * Build the XML body for a single HK control command.
 *
 * @param {string} actionName Wire command, for example `volume-up`.
 * @param {string} zone Receiver zone, commonly `Main Zone` or `Zone 2`.
 * @param {string} para Optional command parameter. Currently used by
 * `source-selection` for exact source labels such as `Disc` or `Radio`.
 * @param {string} templateKey Device template key, usually `avr` or `bds`.
 */
export function generateRequest(actionName, zone, para = '', templateKey = 'avr') {
  const template = TEMPLATES[templateKey] ?? TEMPLATES.avr;
  return template
    .replace('{{ name }}', actionName)
    .replace('{{ zone }}', zone)
    .replace('{{ para }}', para ?? '')
    .trim();
}
