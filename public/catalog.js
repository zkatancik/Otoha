export const inputs = [
  { id: 'tv', name: 'TV', icon: 'tv-minimal', detail: 'Television', wire: 'TV' },
  { id: 'bluetooth', name: 'Bluetooth', icon: 'bluetooth', detail: 'Wireless audio', wire: 'Bluetooth' },
  { id: 'phono', name: 'Phono', icon: 'disc-3', detail: 'Turntable', wire: 'Phono' },
  { id: 'fm', name: 'FM / AM', icon: 'radio', detail: 'Radio tuner', wire: 'FM' },
  { id: 'cd', name: 'CD', icon: 'disc', detail: 'Disc player', wire: 'Disc' },
  { id: 'network', name: 'Network', icon: 'network', detail: 'Media server', wire: 'Home Network' },
  { id: 'usb', name: 'USB / iPod', icon: 'usb', detail: 'Connected device', wire: 'USB' },
  { id: 'cable', name: 'Cable / Sat', icon: 'satellite-dish', detail: 'Set-top box', wire: 'Cable Sat' },
  { id: 'internet', name: 'Internet radio', icon: 'radio-tower', detail: 'vTuner', wire: 'vTuner' },
];
export const remoteKeys = {
  louder: 'volume-up',
  quieter: 'volume-down',
  mute: 'mute-toggle',
  harman: 'harman_volume',
  wake: 'power-on',
  standby: 'standby',
  sleep: 'Sleep',
  play: 'play',
  pause: 'pause',
  next: 'next',
  previous: 'previous',
  menu: 'top-menu',
  back: 'exit',
  up: 'up',
  down: 'down',
  left: 'left',
  right: 'right',
  ok: 'ok',
};

// One hardware button advances through this repeating sequence.
export const harmanModes = ['High', 'Low', 'Off'];
