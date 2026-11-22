import catalog from './receiver-profiles.json' with { type: 'json' };

const models = new Map(Object.entries(catalog.models));
export const profiles = catalog.profiles;

export function matchModel(name) {
  const key = (name || '').trim().toUpperCase().replace(/^HARMAN[\s/.-]*KARDON\s*/, '').replace(/[\s-]/g, '');
  if (key === 'BDS280/80S' || key === 'BDS580/80S') return models.get(key.slice(0, 6) + 'S');
  const speaker = key.replace(/^HK/, '');
  return models.get(key) || (models.get(speaker)?.profile === 'mm' ? models.get(speaker) : null);
}

export function deviceSources(device) {
  const sources = profiles[device.profile].sources;
  return device.model === 'HK 3700' ? sources.filter(s => s.id !== 'bluetooth') : sources;
}
