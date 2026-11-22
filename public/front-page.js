import { inputs, remoteKeys } from './catalog.js';

const commands = (rows) => rows.map(([id, name, icon]) => ({ id, name, icon }));

const commandGroups = [
  { name: 'Listening', items: commands([
    ['quieter', 'Volume down', 'minus'], ['louder', 'Volume up', 'plus'],
    ['mute', 'Mute', 'volume-x'], ['harman', 'Cycle Harman Volume', 'audio-lines'],
    ['mute-on', 'Mute', 'volume-x'], ['mute-off', 'Unmute', 'volume-2'],
  ]) },
  { name: 'Playback', items: commands([
    ['previous', 'Previous', 'skip-back'], ['play', 'Play', 'play'],
    ['pause', 'Pause', 'pause'], ['next', 'Next', 'skip-forward'],
  ]) },
  { name: 'Power', items: commands([
    ['wake', 'Power on', 'power'], ['standby', 'Standby', 'power-off'], ['sleep', 'Sleep timer', 'moon'],
  ]) },
  { name: 'Receiver menu', items: commands([
    ['menu', 'Menu', 'menu'], ['up', 'Up', 'arrow-up'], ['left', 'Left', 'arrow-left'],
    ['ok', 'OK', 'disc'], ['right', 'Right', 'arrow-right'], ['down', 'Down', 'arrow-down'],
    ['back', 'Back', 'arrow-left'],
  ]) },
];

export function frontPageGroups(state) {
  const device = state?.device;
  if (!device) return [];
  const sources = (state.sources || []).map(source => ({
    ...source, icon: inputs.find(input => input.id === source.id)?.icon || 'cable',
  }));
  const actions = new Set(state.actions ?? (device.profile === 'mm'
    ? ['standby', 'mute-on', 'mute-off']
    : Object.keys(remoteKeys).filter(key => key !== 'harman' || device.model === 'HK 3770')));
  return [
    { name: 'Inputs', items: sources.map(source => ({ ...source, id: 'source.' + source.id, source })) },
    ...commandGroups.map(({ name, items }) => ({ name, items: items.filter(item => actions.has(item.id)) })),
  ].filter(group => group.items.length);
}

export function starterSelection(groups) {
  const sources = groups.find(group => group.name === 'Inputs')?.items || [];
  const listening = groups.find(group => group.name === 'Listening')?.items || [];
  const defaults = sources.some(item => item.id === 'source.phono')
    ? sources.filter(item => ['source.phono', 'source.tv'].includes(item.id)) : sources.slice(0, 2);
  return [...defaults, ...listening.filter(item => item.id !== 'harman')].map(item => item.id);
}

export const storageKey = deviceId => 'otoha.frontPage.v1.' + deviceId;

// A missing preference offers setup. An explicitly empty selection keeps the standard remote.
export function readSelection(stored, groups) {
  if (stored === null) return null;
  const ids = new Set(stored.split(','));
  return groups.flatMap(({ items }) => items.filter(({ id }) => ids.has(id)).map(({ id }) => id));
}
