/**
 * Maps friendly JavaScript action keys to Harman Kardon wire commands.
 *
 * This is the app's canonical command catalog. The keys are used by
 * `runStereoAction(actionKey, param)` and by `HKClient.zone(name)`.
 *
 * Most HK commands are fire-and-forget: the receiver accepts a TCP/XML payload
 * but does not return authoritative state. `heartAlive` is the only currently
 * modeled command that reads a response.
 *
 * `selectSource` is the only currently supported parameterized command. Its
 * parameter must be the receiver's exact on-screen source label.
 *
 * Mirrors the upstream PHP command set in HKAPI/lib/Actions/*.php.
 */
export const ACTIONS = {
  back: {
    name: 'back',
    category: 'navigation',
    description: 'Return to the previous receiver menu.',
    hasResponse: false,
  },
  down: {
    name: 'down',
    category: 'navigation',
    description: 'Move down in receiver menus.',
    hasResponse: false,
  },
  forward: {
    name: 'forward',
    category: 'transport',
    description: 'Fast-forward or seek forward in the active media source.',
    hasResponse: false,
  },
  heartAlive: {
    name: 'heart-alive',
    category: 'diagnostic',
    description: 'Ask the receiver control service for a response when supported.',
    hasResponse: true,
  },
  home: {
    name: 'home',
    category: 'navigation',
    description: 'Open the receiver home menu.',
    hasResponse: false,
  },
  info: {
    name: 'info',
    category: 'navigation',
    description: 'Open the receiver info screen.',
    hasResponse: false,
  },
  left: {
    name: 'left',
    category: 'navigation',
    description: 'Move left in receiver menus.',
    hasResponse: false,
  },
  muteToggle: {
    name: 'mute-toggle',
    category: 'volume',
    description: 'Toggle mute. The protocol does not report the new mute state.',
    hasResponse: false,
  },
  next: {
    name: 'next',
    category: 'transport',
    description: 'Skip to the next track, preset, or item in the active source.',
    hasResponse: false,
  },
  off: {
    name: 'power-off',
    category: 'power',
    description: 'Power off the receiver. Some models stop network control afterward.',
    hasResponse: false,
  },
  ok: {
    name: 'ok',
    category: 'navigation',
    description: 'Confirm the current receiver menu selection.',
    hasResponse: false,
  },
  on: {
    name: 'power-on',
    category: 'power',
    description: 'Power on the receiver if its network control service is reachable.',
    hasResponse: false,
  },
  options: {
    name: 'options',
    category: 'navigation',
    description: 'Open the receiver options menu.',
    hasResponse: false,
  },
  pause: {
    name: 'pause',
    category: 'transport',
    description: 'Pause the active media source.',
    hasResponse: false,
  },
  play: {
    name: 'play',
    category: 'transport',
    description: 'Play the active media source.',
    hasResponse: false,
  },
  previous: {
    name: 'previous',
    category: 'transport',
    description: 'Skip to the previous track, preset, or item in the active source.',
    hasResponse: false,
  },
  reverse: {
    name: 'reverse',
    category: 'transport',
    description: 'Rewind or seek backward in the active media source.',
    hasResponse: false,
  },
  right: {
    name: 'right',
    category: 'navigation',
    description: 'Move right in receiver menus.',
    hasResponse: false,
  },
  selectSource: {
    name: 'source-selection',
    category: 'source',
    description: 'Switch to a named receiver source.',
    hasResponse: false,
    takesParam: true,
    paramName: 'source',
    paramDescription: 'Exact source label as shown in the receiver on-screen menu.',
  },
  sleep: {
    name: 'sleep',
    category: 'power',
    description: 'Toggle sleep or set the receiver sleep timer when supported.',
    hasResponse: false,
  },
  up: {
    name: 'up',
    category: 'navigation',
    description: 'Move up in receiver menus.',
    hasResponse: false,
  },
  volumeDown: {
    name: 'volume-down',
    category: 'volume',
    description: 'Lower volume by one receiver step.',
    hasResponse: false,
  },
  volumeUp: {
    name: 'volume-up',
    category: 'volume',
    description: 'Raise volume by one receiver step.',
    hasResponse: false,
  },
};

/**
 * Source labels observed in HKAPI, Home Assistant/Homebridge integrations, and
 * other public wrappers. Treat these as suggestions, not validation rules:
 * `selectSource` must use the exact label configured on the target receiver.
 */
export const KNOWN_SOURCE_LABELS = [
  'Cable Sat',
  'Disc',
  'DVR',
  'Radio',
  'TV',
  'USB',
  'Game',
  'Media Server',
  'Home Network',
  'AUX',
  'Source A',
  'Source B',
  'Source C',
  'Source D',
  'STB',
  'AM',
  'FM',
  'vTuner',
  'Bluetooth',
  'Spotify',
  'Phono',
];
