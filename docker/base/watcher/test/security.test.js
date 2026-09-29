const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const { resolveInside, safePreloadTarget } = require('../index.js');

test('resolveInside keeps paths inside the root', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-'));
  fs.writeFileSync(path.join(root, 'a.txt'), 'x');

  assert.equal(resolveInside(root, 'a.txt'), path.join(root, 'a.txt'));
  assert.equal(resolveInside(root, 'missing/new.txt'), path.join(root, 'missing/new.txt'));
  assert.equal(resolveInside(root, '../etc/passwd'), null);
});

test('resolveInside refuses a sibling that merely shares the prefix', () => {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-'));
  const root = path.join(parent, 'workspace');
  fs.mkdirSync(root);
  fs.mkdirSync(path.join(parent, 'workspace-secrets'));

  assert.equal(resolveInside(root, '../workspace-secrets/key'), null);
});

test('resolveInside refuses a symlink that points out of the root', () => {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-'));
  const root = path.join(parent, 'workspace');
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(parent, 'credentials.json'), '{}');
  fs.symlinkSync(path.join(parent, 'credentials.json'), path.join(root, 'link.json'));

  assert.equal(resolveInside(root, 'link.json'), null);
});

test('safePreloadTarget allows only the serving host under /t/', () => {
  const host = 'flow.example.com';

  assert.equal(
    safePreloadTarget('https://flow.example.com/t/abc/ide/?folder=/workspace', host),
    'https://flow.example.com/t/abc/ide/?folder=/workspace',
  );
  assert.equal(safePreloadTarget('/t/abc/ide/', host), 'http://flow.example.com/t/abc/ide/');
  assert.equal(safePreloadTarget('https://evil.example/t/abc/ide/', host), null);
  assert.equal(safePreloadTarget('//evil.example/t/abc/', host), null);
  assert.equal(safePreloadTarget('javascript:alert(1)', host), null);
  assert.equal(safePreloadTarget('/somewhere-else', host), null);
  assert.equal(safePreloadTarget(null, host), null);
});
