// Redaction of session secrets for the HTTP/2 logger, matching aixle_redact.py.
//
// Two processes append to the same MITM_LOG_PATH — the mitmproxy addon and this
// logger — so the rule has to exist in both languages. The list itself is written by
// the `get_config_item` MCP tool before it answers, so nothing reaches a log ahead of
// the entry that hides it.

const fs = require('fs');

const LIST_PATH = process.env.AIXLE_REDACT_LIST || '/var/log/mitm/redact.list';
const MARKER = '<redacted:session-secret>';

let cacheKey = null;
let cached = [];

// Longest first, so a secret that is a substring of a longer one never corrupts the
// longer replacement.
function values() {
  let stat;
  try {
    stat = fs.statSync(LIST_PATH);
  } catch (_) {
    cacheKey = null;
    cached = [];
    return cached;
  }

  const key = `${stat.mtimeMs}:${stat.size}`;
  if (key === cacheKey) return cached;

  try {
    cached = fs
      .readFileSync(LIST_PATH, 'utf8')
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean)
      .map(line => Buffer.from(line, 'base64').toString('utf8'))
      .filter(Boolean)
      .sort((a, b) => b.length - a.length);
    cacheKey = key;
  } catch (_) {
    // Keep whatever was loaded last rather than logging unredacted on a transient read error.
  }

  return cached;
}

function redactString(text, secrets) {
  let out = text;
  for (const secret of secrets) {
    if (out.includes(secret)) out = out.split(secret).join(MARKER);
  }
  return out;
}

// Walks the entry rather than the serialized line, so a value carrying a quote is
// matched in its own form rather than in JSON's escaping of it.
function redact(entry, secrets) {
  const list = secrets || values();
  if (list.length === 0) return entry;
  if (typeof entry === 'string') return redactString(entry, list);
  if (Array.isArray(entry)) return entry.map(item => redact(item, list));
  if (entry && typeof entry === 'object') {
    const out = {};
    for (const [key, value] of Object.entries(entry)) out[key] = redact(value, list);
    return out;
  }
  return entry;
}

module.exports = { redact, values, MARKER, LIST_PATH };
