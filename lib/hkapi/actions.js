/**
 * Maps friendly method names to HK wire commands.
 * Mirrors HKAPI/lib/Actions/*.php
 */
export const ACTIONS = {
  back: { name: 'back', hasResponse: false },
  down: { name: 'down', hasResponse: false },
  forward: { name: 'forward', hasResponse: false },
  heartAlive: { name: 'heart-alive', hasResponse: true },
  home: { name: 'home', hasResponse: false },
  info: { name: 'info', hasResponse: false },
  left: { name: 'left', hasResponse: false },
  muteToggle: { name: 'mute-toggle', hasResponse: false },
  next: { name: 'next', hasResponse: false },
  off: { name: 'power-off', hasResponse: false },
  ok: { name: 'ok', hasResponse: false },
  on: { name: 'power-on', hasResponse: false },
  options: { name: 'options', hasResponse: false },
  pause: { name: 'pause', hasResponse: false },
  play: { name: 'play', hasResponse: false },
  previous: { name: 'previous', hasResponse: false },
  reverse: { name: 'reverse', hasResponse: false },
  right: { name: 'right', hasResponse: false },
  selectSource: { name: 'source-selection', hasResponse: false, takesParam: true },
  sleep: { name: 'sleep', hasResponse: false },
  up: { name: 'up', hasResponse: false },
  volumeDown: { name: 'volume-down', hasResponse: false },
  volumeUp: { name: 'volume-up', hasResponse: false },
};
