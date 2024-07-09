const api = {
    back: () => console.log('back'),
    down: () => console.log('down'),
    forward: () => console.log('forward'),
    heartAlive: () => console.log('heartAlive'),
    home: () => console.log('home'),
    info: () => console.log('info'),
    left: () => console.log('left'),
    muteToggle: () => console.log('muteToggle'),
    next: () => console.log('next'),
    off: () => console.log('off'),
    ok: () => console.log('ok'),
    on: () => console.log('on'),
    options: () => console.log('options'),
    pause: () => console.log('pause'),
    play: () => console.log('play'),
    previous: () => console.log('previous'),
    reverse: () => console.log('reverse'),
    right: () => console.log('right'),
    selectSource: (source) => console.log(`selectSource: ${source}`),
    up: () => console.log('up'),
    volumeDown: () => console.log('volumeDown'),
    volumeUp: () => console.log('volumeUp'),
  };
  
  export default api;
  