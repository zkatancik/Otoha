import { inputs, harmanModes } from './catalog.js';
import { frontPageGroups, starterSelection, storageKey, readSelection } from './front-page.js';

const $ = (selector) => document.querySelector(selector);
const sheet = $('#sheet');
const sheetBody = $('#sheet-body');
const dial = $('#dial');
const toast = $('#toast');
$('#phone-setup').hidden = !location.hostname.endsWith('.local');
let state = null;
let bridgeOnline = true;
let sheetType = '';
let pending = false;
let stateVersion = 0;
let isReading = false;
let toastTimer;
let currentId;
let sheetSession = 0;
let activeSources = [];
const esc = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let savedPage = null;
let groups = [];
let editorDeviceId;
const sessionPages = new Map();
let viewingFullRemote = false;

function icon(name) {
  return '<svg class="icon" aria-hidden="true"><use href="/assets/icons.svg#' + name + '"></use></svg>';
}
for (const mark of document.querySelectorAll('[data-icon]')) mark.outerHTML = icon(mark.dataset.icon);

function feedback(message) {
  const target = sheet.open && sheetBody.querySelector('.dialog-feedback');
  if (target) target.textContent = message;
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 2900);
}

async function request(route, payload) {
  const opts =
    payload === undefined
      ? {}
      : {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        };
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 14000);
  try {
    const response = await fetch('/api/' + route, {
      ...opts,
      cache: 'no-store',
      signal: controller.signal,
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'The receiver did not respond.');
    return data;
  } finally {
    clearTimeout(timeout);
  }
}

const hardwareKey = label => (label || '').toLowerCase().replace(/\s/g, '');
const portraits = new Map();

function displayPortrait(element, label) {
  const asset = portraits.get(hardwareKey(label));
  if (asset) {
    const path = '/assets/hardware/' + asset + '.webp';
    if (element.getAttribute('src') !== path) element.src = path;
  } else {
    element.removeAttribute('src');
  }
  return Boolean(asset);
}

function showEquipment() {
  const visible = displayPortrait($('#device-portrait'), state?.device?.model);
  $('.hero-art').hidden = !visible;
  const label = visible && state?.irWake ? state?.infrared?.label : '';
  $('#ir-equipment').hidden = !displayPortrait($('#ir-portrait'), label);
  $('#ir-model').textContent = (label || '').replace(/^(Broadlink|Global Caché) /i, '');
}

fetch('/assets/hardware/catalog.json').then(response => response.json()).then(catalog => {
  for (const [label, asset] of Object.entries(catalog)) portraits.set(hardwareKey(label), asset);
  showEquipment();
}).catch(() => { /* Controls stay available when artwork is unavailable. */ });

function applyState() {
  const online = Boolean(bridgeOnline && state?.online);
  const device = state?.device;
  const linked = Boolean(device);
  const speaker = device?.profile === 'mm';
  $('#model').textContent = device?.model || 'Link your device';
  $('#kind').textContent = { mm: 'Wireless speaker', bds3: 'Blu-ray system', bds4: 'Blu-ray system',
    avr: 'AV receiver', stereo: 'Stereo receiver' }[device?.profile] || 'Device setup';
  showEquipment();
  $('#setup-device').hidden = linked;
  $('.hero [data-dialog="power"]').hidden = !linked;
  $('.console').hidden = !linked;
  $('.harman-card').hidden = device?.model !== 'HK 3770';
  $('.volume-card').hidden = speaker;
  $('#speaker-controls').hidden = !speaker;
  $('#set-level').disabled = !online;
  $('#speaker-level').disabled = !online;
  $('.sources').hidden = !state?.sources?.length;
  $('#extra').hidden = !linked || speaker;
  if (device?.id !== currentId) {
    stopHold();
    currentId = device?.id;
    activeSources = state?.sources || [];
    groups = frontPageGroups(state);
    let stored = sessionPages.get(currentId) ?? null;
    if (currentId && stored === null) {
      try {
        stored = localStorage.getItem(storageKey(currentId));
      } catch { /* Storage can be unavailable in a private browser session. */ }
    }
    savedPage = readSelection(stored, groups);
    viewingFullRemote = false;
    renderFrontPage();
    const quick = device?.profile === 'stereo'
      ? ['phono', 'tv'].map(id => activeSources.find(s => s.id === id)).filter(Boolean)
      : activeSources.slice(0, 2);
    $('#quick-inputs').innerHTML = quick.map(s => sourceButton(s, true)).join('');
    $('#speaker-level').value = 0;
    $('#speaker-value').textContent = '0%';
    if (sheet.open && sheetType !== 'receiver') sheet.close();
  }
  const status = $('#connection');
  status.classList.toggle('online', online);
  status.lastElementChild.textContent = !bridgeOnline
    ? 'Bridge offline'
    : !state
      ? 'Connecting'
      : online
        ? 'Connected'
        : linked ? 'Offline' : 'No device linked';
  const notice = $('#connection-notice');
  notice.hidden = bridgeOnline && (!linked || online);
  $('#notice-text').textContent = bridgeOnline
    ? 'The linked device is unreachable. Check its power and network connection.'
    : 'Check that your Mac is awake and connected to your home network.';
  for (const btn of document.querySelectorAll('[data-action],[data-source],[data-step]')) {
    btn.disabled = btn.dataset.action === 'wake' ? !bridgeOnline : !online;
  }
  const tracked = online ? state.trackedMode : null;
  $('#tracked-controls').hidden = !tracked;
  $('#cycle-controls').hidden = Boolean(tracked);
  for (const button of document.querySelectorAll('[data-mode]')) {
    button.disabled = !online;
    button.setAttribute('aria-pressed', String(button.dataset.mode === tracked));
  }
  for (const button of document.querySelectorAll('[data-sync]')) button.disabled = !online;
  dial.setAttribute('aria-disabled', String(!online));
  for (const btn of document.querySelectorAll('[data-source]')) {
    const selected = online && state.lastSource === btn.dataset.source;
    btn.classList.toggle('requested', selected);
    const source = activeSources.find((i) => i.id === btn.dataset.source);
    if (!source) continue;
    btn.querySelector('small').textContent = selected ? 'Last requested' : source.detail;
  }
  if (sheetType === 'receiver') updateReceiver();
  if (sheetType === 'infrared') updateInfrared();
  if (sheetType === 'manualInfrared') {
    const save = $('#save-webhook');
    save.disabled = pending || !bridgeOnline || !$('#wake-webhook').value.trim() ||
      !['idle', 'choose', 'error'].includes(state?.infrared?.phase);
  }
  if (sheetType === 'power' && $('#infrared-entry')) {
    $('#infrared-entry').textContent = state?.irWake ? 'Infrared wake' : 'Set up infrared wake';
    $('#infrared-entry').disabled = !bridgeOnline;
    const subtitle = sheetBody.querySelector('[data-action="wake"] small');
    if (subtitle) subtitle.textContent = state?.irWake ? 'Send the infrared On command.' : 'Try network wake while the receiver is reachable.';
  }
}

function offerFrontPage() {
  if (currentId && groups.length && savedPage === null && bridgeOnline && !sheetType && !sheet.open)
    openSheet('frontPage');
}

async function refresh() {
  if (isReading || pending || document.hidden) return;
  isReading = true;
  const version = stateVersion;
  try {
    const next = await request('state');
    if (version === stateVersion) {
      state = next;
      bridgeOnline = true;
      applyState();
      offerFrontPage();
    }
  } catch {
    if (version === stateVersion) {
      bridgeOnline = false;
      applyState();
    }
  } finally {
    isReading = false;
  }
}

async function command(action, value, silent = false) {
  if (pending) return false;
  pending = true;
  stateVersion++;
  try {
    const result = await request('command', { action, value, targetId: state?.device?.id });
    if (state && 'trackedMode' in result) state.trackedMode = result.trackedMode;
    if (state && 'lastSource' in result) state.lastSource = result.lastSource;
    if (!silent) {
      if (['source', 'standby', 'wake', 'sync-mode'].includes(action) && sheet.open) sheet.close();
      feedback(result.message);
    }
    applyState();
    if (action === 'standby' || action === 'wake' || action === 'network-volume')
      setTimeout(refresh, 850);
    return true;
  } catch (error) {
    feedback(error.message === 'Failed to fetch' ? 'The home bridge is unreachable.' : error.message);
    setTimeout(refresh, 100);
    return false;
  } finally {
    stateVersion++;
    pending = false;
  }
}

function sourceButton(source, quick) {
  let art = icon(inputs.find(input => input.id === source.id)?.icon || 'cable');
  if (quick) {
    if (source.id === 'phono') art = '<i class="vinyl"></i>';
    if (source.id === 'tv') art = '<i class="tv-art"></i>';
    art = '<span class="source-art ' + (source.id === 'tv' ? 'television' : '') +
      '" aria-hidden="true">' + art + '</span>';
  }
  return (
    '<button type="button" class="' +
    (quick ? 'source-card' : 'source-row') +
    '" data-source="' +
    esc(source.id) +
    '">' +
    art +
    '<span class="source-identity"><strong>' +
    esc(source.name) +
    '</strong><small>' +
    esc(source.detail) +
    '</small></span>' +
    icon('chevron-right') +
    '</button>'
  );
}

function renderFrontPage() {
  const active = Boolean(savedPage?.length) && !viewingFullRemote;
  $('#front-page').hidden = !active;
  $('#full-remote').hidden = active;
  $('#return-front').hidden = !savedPage?.length;
  $('#front-groups').innerHTML = groups.map(({ name, items }) => {
    const chosen = items.filter((item) => savedPage?.includes(item.id));
    if (!chosen.length) return '';
    const buttons = chosen.map((item) => item.source
      ? sourceButton(item.source, true)
      : '<button class="shortcut-key" data-action="' + item.id + '">' + icon(item.icon) + item.name + '</button>');
    return '<h3>' + name + '</h3><div class="' + (chosen[0].source ? 'quick-inputs' : 'shortcut-grid') +
      '">' + buttons.join('') + '</div>';
  }).join('');
}

function saveFrontPage(selected) {
  if (!currentId || currentId !== editorDeviceId) return 'The linked device changed.';
  savedPage = selected;
  let message = selected.length ? 'Front page saved.' : 'Using the standard remote.';
  const stored = selected.join(',');
  try {
    localStorage.setItem(storageKey(currentId), stored);
    sessionPages.delete(currentId);
  } catch {
    sessionPages.set(currentId, stored);
    message = 'Your browser can only keep this layout for this session.';
  }
  viewingFullRemote = false;
  renderFrontPage();
  applyState();
  return message;
}

function renderPicker() {
  editorDeviceId = currentId;
  const draft = savedPage?.length ? savedPage : starterSelection(groups);
  const sections = groups.map(({ name, items }) =>
    '<fieldset><legend>' + name + '</legend>' + items.map((item) =>
      '<label class="picker-choice">' + icon(item.icon) + esc(item.name) +
      '<input type="checkbox" value="' + esc(item.id) + '"' + (draft.includes(item.id) ? ' checked' : '') +
      '></label>').join('') + '</fieldset>').join('');
  sheetBody.innerHTML = '<p class="sheet-copy">Choose the inputs and commands you use most. You can edit your front page anytime.</p>' +
    '<div class="picker-choices">' + sections + '</div><div class="picker-actions">' +
    (savedPage?.length ? '<button class="text-action" id="standard-remote">Use standard remote</button>' :
      '<button class="text-action" id="dismiss-picker">' + (savedPage === null ? 'Skip' : 'Cancel') + '</button>') +
    '<button class="save-page" id="save-front">Save front page</button></div>';
  const selected = () => Array.from(sheetBody.querySelectorAll('input:checked'), (input) => input.value);
  $('#save-front').disabled = !selected().length;
  sheetBody.querySelector('.picker-choices').onchange = () => { $('#save-front').disabled = !selected().length; };
  const finish = (items) => {
    const message = saveFrontPage(items);
    sheet.close();
    if (items.length) $('#front-title').focus();
    feedback(message);
  };
  $('#save-front').onclick = () => finish(selected());
  if ($('#standard-remote')) $('#standard-remote').onclick = () => finish([]);
  if ($('#dismiss-picker')) $('#dismiss-picker').onclick = () => sheet.close();
}

$('#show-full').onclick = () => {
  viewingFullRemote = true;
  renderFrontPage();
  applyState();
  $('#return-front').focus();
};
$('#return-front').onclick = () => {
  viewingFullRemote = false;
  renderFrontPage();
  applyState();
  $('#front-title').focus();
};
$('#mode-choices').innerHTML = harmanModes
  .map((mode) => '<button data-mode="' + mode + '">' + mode + '</button>')
  .join('');
const keyButton = ([action, label, glyph]) =>
  '<button data-action="' +
  action +
  '" aria-label="' +
  label +
  '" title="' +
  label +
  '">' +
  (glyph ? icon(glyph) : label) +
  '</button>';
$('#transport').innerHTML = [
  ['previous', 'Previous', 'skip-back'],
  ['play', 'Play', 'play'],
  ['pause', 'Pause', 'pause'],
  ['next', 'Next', 'skip-forward'],
]
  .map(keyButton)
  .join('');
$('#dpad').innerHTML = [
  ['menu', 'Menu'],
  ['left', 'Left', 'arrow-left'],
  ['up', 'Up', 'arrow-up'],
  ['ok', 'OK'],
  ['down', 'Down', 'arrow-down'],
  ['right', 'Right', 'arrow-right'],
  ['back', 'Exit'],
]
  .map(keyButton)
  .join('');
function choice(action, title, text, glyph) {
  return (
    '<button data-action="' +
    action +
    '" class="choice">' +
    icon(glyph) +
    '<span class="choice-text"><strong>' +
    title +
    '</strong><small>' +
    text +
    '</small></span>' +
    icon('chevron-right') +
    '</button>'
  );
}
function openSheet(type) {
  if (type === 'frontPage' && !currentId) return;
  stopHold();
  sheetType = type;
  const session = ++sheetSession;
  sheet.classList.toggle('front-page-editor', type === 'frontPage');
  $('#sheet-title').textContent = {
    phone: 'Use on a phone',
    receiver: 'Locate and link',
    power: 'Power',
    infrared: 'Infrared wake',
    manualInfrared: 'Link an unlisted blaster',
    inputs: 'All inputs',
    mode: 'Sync Harman Volume',
    frontPage: savedPage === null ? 'Set up front page' : 'Edit front page',
  }[type];
  if (type === 'phone') {
    sheetBody.innerHTML = '<p class="sheet-copy">Join your home Wi-Fi, open Camera on your phone, and point it at this code. Tap the link to open your remote.</p>' +
      '<img class="phone-code" alt="QR code to open this remote on home Wi-Fi">' +
      '<p class="sheet-note">You can also use Share → AirDrop in Safari on your Mac to send this page to your iPhone.</p>';
    const code = sheetBody.querySelector('.phone-code');
    code.onerror = () => { code.hidden = true; sheetBody.querySelector('.sheet-copy').textContent = 'The code couldn’t load. Join your home Wi-Fi and share this page with your phone.'; };
    code.src = '/phone-setup.png';
  }
  if (type === 'frontPage') renderPicker();
  if (type === 'mode')
    sheetBody.innerHTML =
      '<p class="sheet-copy">Which mode is on the receiver’s front display? Otoha can track its own button presses from there and let you pick a mode directly.</p><div class="sheet-list">' +
      harmanModes
        .map(
          (mode) =>
            '<button class="choice" data-sync="' + mode + '"><strong>' + mode + '</strong></button>',
        )
        .join('') +
      '</div><p class="sheet-note power-note">Sync again after using the physical handset or front-panel button.</p>';
  if (type === 'inputs')
    sheetBody.innerHTML =
      '<div class="sheet-list">' + activeSources.map((i) => sourceButton(i, false)).join('') + '</div>';
  if (type === 'power')
    sheetBody.innerHTML =
      '<div class="sheet-list">' +
      (state?.device?.profile === 'mm' ? '' : choice(
        'wake',
        'Power on',
        state?.irWake
          ? 'Send the infrared On command.'
          : 'Try network wake while the receiver is reachable.',
        'power',
      )) +
      choice('standby', 'Standby', 'Put the stereo into standby.', 'power-off') +
      (state?.device?.profile === 'mm' ? '' : choice('sleep', 'Sleep timer', 'Advance the timer on the receiver display.', 'moon')) +
      '</div><p class="sheet-note power-note">If standby shuts down Ethernet, waking the stereo requires its On button or an infrared bridge.</p>' +
      (state?.infrared ? '<button class="sheet-button" id="infrared-entry" data-dialog="infrared">Set up infrared wake</button>' : '');
  if (type === 'infrared')
    sheetBody.innerHTML = '<div id="infrared-setup" aria-live="polite"></div><button class="text-action" data-dialog="power">Back to Power</button>';
  if (type === 'manualInfrared') {
    const receiverId = state?.infrared?.receiverId;
    sheetBody.innerHTML =
      '<ol class="sheet-copy ir-guide"><li>Aim the emitter at your HK 3770. In the blaster’s app, select Power On for the receiver, or teach it the On button from the original remote. A power toggle can turn the receiver off.</li>' +
      '<li>Set your blaster or a home automation hub, such as Home Assistant, to send that command when it receives an empty HTTP POST. Copy the webhook URL using a private IPv4 address or a .local hostname.</li></ol>' +
      '<details class="sheet-copy"><summary>Home Assistant example</summary><p>In Settings → Automations &amp; scenes, create an automation with a Webhook trigger. Allow POST and keep local access enabled. Add the blaster’s saved On command as the action, save the automation, and copy the trigger’s local URL.</p></details>' +
      '<form id="webhook-form"><label class="sheet-label" for="wake-webhook">Power-on webhook URL</label>' +
      '<input id="wake-webhook" type="password" inputmode="url" autocomplete="off" autocapitalize="none" spellcheck="false" maxlength="2048" required>' +
      '<p class="sheet-note">Saving links this blaster to your receiver. Use Power on when you’re ready to try it.</p>' +
      '<button class="sheet-button" id="save-webhook" type="submit">Link blaster</button></form>' +
      '<button class="text-action" data-dialog="infrared">Back to infrared wake</button>';
    const input = $('#wake-webhook');
    input.oninput = applyState;
    $('#webhook-form').onsubmit = async event => {
      event.preventDefault();
      if ($('#save-webhook').disabled || state?.infrared?.receiverId !== receiverId) return;
      const current = () => sheet.open && session === sheetSession;
      pending = true;
      stateVersion++;
      applyState();
      try {
        await configureInfrared({ action: 'manual', receiverId, url: input.value.trim() });
        if (current()) openSheet('infrared');
      } catch (error) {
        if (current()) feedback(error.message);
      } finally {
        pending = false;
        stateVersion++;
        applyState();
      }
    };
  }
  if (type === 'receiver')
    sheetBody.innerHTML =
      '<p class="sheet-copy">Turn on your stereo and connect it to the same home router as your computer, using Wi-Fi or a network cable. Choose your stereo below.</p>' +
      '<div class="sheet-row"><span>Linked device</span><strong id="receiver-host"></strong></div>' +
      '<button class="sheet-button" id="discover">Locate devices</button><div class="sheet-list" id="found-devices"></div>' +
      '<button class="sheet-button" data-dialog="frontPage" id="edit-front-page">Edit front page</button>' +
      '<div id="renderer-settings"><h3 class="sheet-subtitle">Network playback level</h3><p class="sheet-note">DLNA playback level can differ from the amplifier volume.</p><label class="sheet-label" for="network-level">Playback level <output id="network-value"></output></label><input class="sheet-range" type="range" id="network-level" min="0" max="100" step="1"></div>';
  sheetBody.insertAdjacentHTML('beforeend', '<p class="dialog-feedback" role="status"></p>');
  if (!sheet.open) sheet.showModal();
  else {
    sheet.scrollTop = 0;
    $('#close').focus();
  }
  applyState();
  if (type === 'receiver') {
    const locate = $('#discover');
    const results = $('#found-devices');
    const current = () => sheet.open && session === sheetSession;
    locate.onclick = async () => {
      locate.disabled = true;
      locate.textContent = 'Locating…';
      results.replaceChildren();
      feedback('Looking for devices on your network…');
      try {
        const { devices } = await request('devices', {});
        if (!current()) return;
        feedback(devices.length ? 'Choose the device to link.' : 'No stereo found yet. Check that it’s on and connected to your home router. Allow Otoha Bridge under Local Network on your Mac, then choose Locate again.');
        for (const device of devices) {
          const row = document.createElement('button');
          row.className = 'choice';
          row.textContent = 'Link ' + device.name + (device.name === device.model ? '' : ' · ' + device.model);
          if (devices.filter(d => d.name === device.name && d.model === device.model).length > 1)
            row.textContent += ' · Device ID ending in ' + device.id.slice(-6);
          row.onclick = async () => {
            if (pending) return;
            pending = true;
            stateVersion++;
            locate.disabled = true;
            for (const button of results.children) button.disabled = true;
            feedback('Connecting to ' + device.model + '…');
            try {
              state = await request('link', { id: device.id });
              bridgeOnline = true;
              applyState();
              if (current()) sheet.close();
              feedback('Linked to ' + device.name + '.');
            } catch (error) {
              if (current()) feedback(error.message);
            } finally {
              pending = false;
              stateVersion++;
              locate.disabled = false;
              for (const button of results.children) button.disabled = false;
            }
          };
          results.append(row);
        }
      } catch (error) {
        if (current()) feedback(error.message);
      } finally {
        locate.disabled = false;
        locate.textContent = 'Locate again';
      }
    };
    locate.click();
    $('#network-level').oninput = (event) => {
      event.target.dataset.editing = 'true';
      $('#network-value').textContent = event.target.value + '%';
    };
    $('#network-level').onchange = async (event) => {
      const slider = event.target;
      await command('network-volume', Number(slider.value));
      delete slider.dataset.editing;
      await refresh();
    };
    $('#network-level').onpointercancel = (e) => {
      delete e.target.dataset.editing;
      updateReceiver();
    };
  }
}

function updateReceiver() {
  const slider = $('#network-level');
  if (!slider) return;
  const device = state?.device;
  $('#receiver-host').textContent = device ? [...new Set([device.name, device.model])].join(' · ') : 'None';
  $('#edit-front-page').hidden = !currentId;
  $('#renderer-settings').hidden = !Number.isInteger(state?.networkVolume);
  slider.disabled = !bridgeOnline || !Number.isInteger(state?.networkVolume);
  if (!slider.dataset.editing) {
    slider.value = state?.networkVolume ?? 0;
    $('#network-value').textContent = slider.disabled ? 'Unavailable' : slider.value + '%';
  }
}

async function configureInfrared(payload) {
  const result = await request('infrared', payload);
  if (state?.infrared?.receiverId === result.receiverId) {
    state.infrared = result;
    state.irWake = ['linked', 'external'].includes(result.phase);
  }
}

function updateInfrared() {
  const root = $('#infrared-setup');
  if (!root) return;
  const setup = state?.infrared;
  const signature = JSON.stringify([setup, bridgeOnline, pending]);
  if (root.dataset.rendered === signature) return;
  root.dataset.rendered = signature;
  root.replaceChildren();
  const add = (tag, css, text) => {
    const element = document.createElement(tag);
    element.className = css;
    element.textContent = text;
    root.append(element);
    return element;
  };
  const submit = (title, action, id) => {
    const button = add('button', 'sheet-button', title);
    button.disabled = pending || !bridgeOnline;
    button.onclick = async () => {
      if (pending || (action === 'forget' && !window.confirm('Forget this blaster and use network wake again?'))) return;
      pending = true;
      stateVersion++;
      updateInfrared();
      try {
        await configureInfrared({ action, id, receiverId: setup.receiverId });
      } catch (error) {
        feedback(error.message);
      } finally {
        pending = false;
        stateVersion++;
        applyState();
      }
    };
  };
  if (!setup || !bridgeOnline) {
    add('p', 'sheet-copy', 'Reconnect to your HK 3770 to manage infrared wake.');
  } else if (setup.phase === 'linked' || setup.phase === 'broken') {
    if (setup.label) add('h3', 'sheet-subtitle', setup.label + ' linked');
    add('p', 'sheet-copy', setup.message || 'Power on now sends the HK 3770’s infrared On signal.');
    submit('Forget blaster', 'forget');
  } else if (setup.phase === 'external') {
    add('p', 'sheet-copy', 'Power on already uses the infrared controller configured on your home bridge.');
  } else if (setup.phase === 'searching' || setup.phase === 'linking') {
    add('h3', 'sheet-subtitle', setup.phase === 'searching' ? 'Finding blasters…' : 'Linking blaster…');
    add('p', 'sheet-copy', 'This can take about a minute. You can leave this screen while your bridge finishes setup.');
  } else if (setup.phase === 'choose') {
    add('p', 'sheet-copy', 'Choose the blaster near your receiver.');
    for (const device of setup.devices)
      submit(device.label + ' · ID ending in ' + device.id.slice(-6), 'select', device.id);
    submit('Search again', 'search');
  } else {
    add('p', 'sheet-copy', 'An infrared blaster can wake your HK 3770 the same way its original remote does. Plug the blaster in, connect it to your home network, and point it at the front of the stereo.');
    const tips = add('details', 'sheet-copy', '');
    const summary = document.createElement('summary');
    summary.textContent = 'Compatible blasters and setup tips';
    const instructions = document.createElement('p');
    instructions.textContent = 'Otoha supports BroadLink RM, IRKit, Nature Remo models with a local API, Tasmota IR transmitters, and Global Caché iTach IP2IR, WF2IR and Flex IR. For BroadLink, turn off Lock device in its app. For iTach, use the first IR output. Tasmota needs Bonjour advertising, local HTTP access and an IRsend pin.';
    tips.append(summary, instructions);
    add('p', 'sheet-note', 'Your bridge will search once and link a single match. The first search may download discovery drivers. Only Power on sends the signal.');
    if (setup.message) add('p', 'sheet-copy', setup.message);
    submit('Find and link a blaster', 'search');
  }
  if (bridgeOnline && ['idle', 'choose', 'error'].includes(setup?.phase)) {
    const manual = add('button', 'text-action', 'Not listed');
    manual.dataset.dialog = 'manualInfrared';
    manual.disabled = pending;
  }
}

$('#speaker-level').oninput = e => { $('#speaker-value').textContent = e.target.value + '%'; };
$('#set-level').onclick = () => command('speaker-volume', Number($('#speaker-level').value));
$('#close').onclick = () => sheet.close();
sheet.addEventListener('close', () => {
  if (sheet.open) return;
  if (sheetType === 'manualInfrared') sheetBody.replaceChildren();
  if (sheetType === 'frontPage' && editorDeviceId === currentId && savedPage === null) feedback(saveFrontPage([]));
  sheetType = '';
  offerFrontPage();
});
sheet.addEventListener('click', (e) => {
  const r = sheet.getBoundingClientRect();
  if (
    e.target === sheet &&
    (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom)
  )
    sheet.close();
});
document.addEventListener('click', (event) => {
  const btn = event.target.closest('button');
  if (!btn || btn.disabled) return;
  if (btn.dataset.dialog) openSheet(btn.dataset.dialog);
  if (btn.dataset.sync) command('sync-mode', btn.dataset.sync);
  if (btn.dataset.mode) command('set-mode', btn.dataset.mode);
  if (btn.dataset.action) command(btn.dataset.action);
  if (btn.dataset.source) command('source', btn.dataset.source);
  if (btn.dataset.step && event.detail === 0) step(btn.dataset.step);
});

let hold = null;
let dialDrag = null;
let flashTimer;
function stopHold() {
  if (hold) {
    clearTimeout(hold.timer);
    hold.btn.classList.remove('held');
    hold = null;
  }
  dialDrag = null;
}
async function step(action) {
  if (!bridgeOnline || !state?.online || pending) return false;
  dial.classList.toggle('up', action === 'louder');
  dial.classList.toggle('down', action === 'quieter');
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => dial.classList.remove('up', 'down'), 150);
  return command(action, undefined, true);
}
for (const btn of document.querySelectorAll('[data-step]')) {
  btn.addEventListener('pointerdown', async (e) => {
    if (e.button !== 0 || !e.isPrimary || btn.disabled) return;
    stopHold();
    const key = (hold = { btn, timer: 0 });
    btn.classList.add('held');
    btn.setPointerCapture(e.pointerId);
    const began = performance.now();
    const repeat = async () => {
      if (key !== hold || document.hidden) return;
      if (performance.now() - began > 4500 || !(await step(btn.dataset.step))) {
        if (hold === key) stopHold();
        return;
      }
      if (key === hold) key.timer = setTimeout(repeat, 230);
    };
    const sent = await step(btn.dataset.step);
    if (key === hold && sent) key.timer = setTimeout(repeat, 410);
    else if (key === hold) stopHold();
  });
  btn.addEventListener('contextmenu', (e) => e.preventDefault());
  btn.addEventListener('pointermove', (event) => {
    if (hold?.btn !== btn) return;
    const box = btn.getBoundingClientRect();
    if (
      event.clientX < box.left ||
      event.clientX > box.right ||
      event.clientY < box.top ||
      event.clientY > box.bottom
    )
      stopHold();
  });
  btn.addEventListener('lostpointercapture', stopHold);
}
dial.onpointerdown = (e) => {
  if (!e.isPrimary || e.button !== 0 || !state?.online || !bridgeOnline) return;
  dial.setPointerCapture(e.pointerId);
  dialDrag = { y: e.clientY, id: e.pointerId, at: 0 };
};
dial.onpointermove = (e) => {
  if (!dialDrag || e.pointerId !== dialDrag.id || pending) return;
  const dy = dialDrag.y - e.clientY;
  if (Math.abs(dy) < 8 || performance.now() - dialDrag.at < 130) return;
  dialDrag.y = e.clientY;
  dialDrag.at = performance.now();
  step(dy > 0 ? 'louder' : 'quieter');
};
dial.onkeydown = (e) => {
  if (['ArrowUp', 'ArrowRight', 'ArrowDown', 'ArrowLeft'].includes(e.key)) {
    e.preventDefault();
    if (!e.repeat) step(['ArrowUp', 'ArrowRight'].includes(e.key) ? 'louder' : 'quieter');
  }
};
for (const event of ['pointerup', 'pointercancel', 'blur', 'pagehide'])
  window.addEventListener(event, stopHold);
document.addEventListener('visibilitychange', () => {
  stopHold();
  if (!document.hidden) refresh();
});

function drawWave() {
  const canvas = $('#waves');
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  const w = canvas.width,
    h = canvas.height;
  for (let row = 0; row < 15; row++) {
    ctx.beginPath();
    ctx.strokeStyle = 'rgba(110, 83, 137,' + (0.2 + row * 0.026) + ')';
    ctx.lineWidth = 1.45;
    for (let x = 0; x <= w; x += 2) {
      const t = x / w;
      const amplitude = 12 + 33 * Math.sin(t * Math.PI) ** 2;
      const y =
        h * 0.46 + (row - 7) * 3.2 + Math.sin(t * 9 + row * 0.125) * amplitude * Math.sin(t * Math.PI);
      if (!x) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();
  }
}
drawWave();
renderFrontPage();
applyState();
refresh();
setInterval(refresh, 6000);
