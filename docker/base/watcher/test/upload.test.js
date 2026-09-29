const assert = require('node:assert/strict');
const { test } = require('node:test');

const { uploadFileName } = require('../index.js');

const now = new Date('2026-09-28T03:04:05.678Z');

test('uploadFileName names an image by its type', () => {
  assert.equal(uploadFileName('image/png', now, () => 0.5), 'paste-20260928-030405-8000.png');
  assert.equal(uploadFileName('image/jpeg; charset=binary', now, () => 0), 'paste-20260928-030405-0000.jpg');
  assert.equal(uploadFileName('IMAGE/WEBP', now, () => 0), 'paste-20260928-030405-0000.webp');
});

test('uploadFileName refuses what an agent CLI cannot attach', () => {
  assert.equal(uploadFileName('image/svg+xml', now), null);
  assert.equal(uploadFileName('text/plain', now), null);
  assert.equal(uploadFileName(undefined, now), null);
});
