const assert = require('node:assert/strict');
const { test } = require('node:test');

const { checkAuthComplete } = require('../index.js');

const KIRO_MARKERS = [
  '__contains__:access_token',
  '__contains__:refresh_token',
  '__contains__:api.codewhisperer.profile',
];

const TOKEN_ROW = 'kirocli:odic:token{"access_token":"aoa","refresh_token":"aor"}';
const PROFILE_ROW = 'api.codewhisperer.profile{"arn":"arn:aws:codewhisperer:us-east-1:1:profile/A"}';

test('a Kiro login is complete once the token and the selected profile are both stored', () => {
  assert.equal(checkAuthComplete(`SQLite format 3\0${TOKEN_ROW}${PROFILE_ROW}`, KIRO_MARKERS), true);
});

test('an organisation login stopped at the profile prompt is not complete', () => {
  assert.equal(checkAuthComplete(`SQLite format 3\0${TOKEN_ROW}`, KIRO_MARKERS), false);
});

test('a database holding only the device registration is not complete', () => {
  assert.equal(checkAuthComplete('SQLite format 3\0kirocli:odic:device{"clientId":"x"}', KIRO_MARKERS), false);
});

test('nothing to read is never complete', () => {
  assert.equal(checkAuthComplete('', KIRO_MARKERS), false);
  assert.equal(checkAuthComplete(null, KIRO_MARKERS), false);
  assert.equal(checkAuthComplete(`${TOKEN_ROW}${PROFILE_ROW}`, []), false);
});

test('JSON keys still complete on any one of them', () => {
  const keys = ['oauthAccount.accountUuid', 'primaryApiKey'];

  assert.equal(checkAuthComplete(JSON.stringify({ primaryApiKey: 'sk' }), keys), true);
  assert.equal(checkAuthComplete(JSON.stringify({ oauthAccount: { accountUuid: 'u' } }), keys), true);
  assert.equal(checkAuthComplete(JSON.stringify({ oauthAccount: {} }), keys), false);
});
