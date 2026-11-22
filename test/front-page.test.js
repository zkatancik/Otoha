import test from 'node:test';
import assert from 'node:assert/strict';
import { frontPageGroups, readSelection, starterSelection, storageKey } from '../public/front-page.js';

test('the picker uses the linked device’s commands and inputs', () => {
  assert.deepEqual(frontPageGroups({ linked: false }), []);
  const groups = frontPageGroups({
    device: { id: 'living-room', model: 'BDS 580', profile: 'bds4' },
    sources: [{ id: 'hdmi1', name: 'HDMI 1', detail: 'HDMI input' }],
    actions: ['play', 'pause', 'mute'],
  });
  assert.deepEqual(starterSelection(groups), ['source.hdmi1', 'mute']);
  assert.deepEqual(readSelection('source.phono,source.hdmi1,harman,play,play', groups), ['source.hdmi1', 'play']);
  assert.equal(groups[0].items[0].source.id, 'hdmi1');
});

test('skipping setup is remembered separately from an unseen device', () => {
  const groups = frontPageGroups({ device: { profile: 'mm' }, sources: [] });
  const memory = new Map([[storageKey('speaker-a'), '']]);
  assert.deepEqual(readSelection(memory.get(storageKey('speaker-a')), groups), []);
  assert.equal(readSelection(memory.get(storageKey('speaker-b')) ?? null, groups), null);
  assert.deepEqual(starterSelection(groups), ['mute-on', 'mute-off']);
  assert.deepEqual(readSelection('mute,source.tv,mute-off,standby', groups), ['mute-off', 'standby']);
});
