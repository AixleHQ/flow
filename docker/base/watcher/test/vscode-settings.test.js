const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const { vscodeUserSettings } = require('../index.js');

const settingsFile = () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'vsc-')), 'settings.json');
  fs.writeFileSync(file, JSON.stringify({ 'workbench.colorTheme': 'Default Dark Modern', 'editor.fontSize': 14 }));
  return file;
};

test('vscodeUserSettings sets the theme for the scheme and keeps the rest', () => {
  const light = JSON.parse(vscodeUserSettings('light', settingsFile()));

  assert.equal(light['workbench.colorTheme'], 'Default Light Modern');
  assert.equal(light['editor.fontSize'], 14);
  assert.equal(JSON.parse(vscodeUserSettings('dark', settingsFile()))['workbench.colorTheme'], 'Default Dark Modern');
});

test('vscodeUserSettings falls back to dark for anything else', () => {
  assert.equal(JSON.parse(vscodeUserSettings('<script>', settingsFile()))['workbench.colorTheme'], 'Default Dark Modern');
});

test('vscodeUserSettings is null without the settings file', () => {
  assert.equal(vscodeUserSettings('light', '/nonexistent/settings.json'), null);
});
