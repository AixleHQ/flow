// Redaction of session secrets for the HTTP/2 logger, matching aixle_redact.py.
//
// Two processes append to the same MITM_LOG_PATH — the mitmproxy addon and this
// logger — so the rule has to exist in both languages: secrets are looked for in a
// string's significant characters (escape sequences, whitespace, control and
// box-drawing characters dropped), and a secret of FRAGMENT_FLOOR characters or more
// is also masked in its FRAGMENT-character pieces that mix letter cases or letters and
// digits. aixle_redact.py says why.

const fs = require('fs');

const LIST_PATH = process.env.AIXLE_REDACT_LIST || '/var/log/mitm/redact.list';
const MARKER = '<redacted:session-secret>';
const FRAGMENT = 8;
const FRAGMENT_FLOOR = 16;

let cacheKey = null;
let cached = [];
let needlesKey = null;
let needlesCached = [];

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

function significant(ch) {
  if (/\s/u.test(ch)) return false;
  const code = ch.codePointAt(0);
  if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) return false;
  return !(code >= 0x2500 && code <= 0x259f);
}

// Characters of `text` (code points) worth matching, and where each one sits.
function project(chars) {
  const sig = [];
  const where = [];
  for (let i = 0; i < chars.length; i++) {
    if (chars[i] === '\x1b') {
      const next = chars[i + 1];
      if (next === '[') {
        let j = i + 2;
        while (j < chars.length && /[\x20-\x3f]/.test(chars[j])) j++;
        i = j;
      } else if (next !== undefined && ']PX^_'.includes(next)) {
        let j = i + 2;
        while (j < chars.length && chars[j] !== '\x07' && !(chars[j] === '\x1b' && chars[j + 1] === '\\')) j++;
        i = chars[j] === '\x1b' ? j + 1 : j;
      } else {
        i += 1;
      }
      continue;
    }
    if (significant(chars[i])) {
      sig.push(chars[i]);
      where.push(i);
    }
  }
  return { sig: sig.join(''), where };
}

function needles(secrets) {
  const key = secrets.join('\u0000');
  if (key === needlesKey) return needlesCached;
  const found = new Set();
  for (const secret of secrets) {
    const sig = Array.from(secret).filter(significant).join('');
    const points = Array.from(sig);
    if (sig) found.add(sig);
    // A short secret also without the punctuation at its ends (aixle_redact.core says why).
    const core = sig.replace(/^[\W_]+|[\W_]+$/gu, '');
    if (points.length < FRAGMENT_FLOOR && core !== sig && Array.from(core).length >= FRAGMENT) found.add(core);
    if (points.length >= FRAGMENT_FLOOR) {
      for (let i = 0; i + FRAGMENT <= points.length; i++) {
        const piece = points.slice(i, i + FRAGMENT).join('');
        if ([/\p{Ll}/u, /\p{Lu}/u, /\p{Nd}/u].filter(kind => kind.test(piece)).length >= 2) found.add(piece);
      }
    }
  }
  needlesKey = key;
  needlesCached = Array.from(found).sort((a, b) => b.length - a.length);
  return needlesCached;
}

// The code-point indexes of `sig` covered by a secret or a piece of one.
function cover(sig, list) {
  const points = Array.from(sig);
  const offsets = [];
  let unit = 0;
  for (const point of points) {
    offsets.push(unit);
    unit += point.length;
  }
  const byUnit = new Map(offsets.map((offset, index) => [offset, index]));
  const flags = new Uint8Array(points.length);
  for (const needle of list) {
    const size = Array.from(needle).length;
    let at = sig.indexOf(needle);
    while (at !== -1) {
      const first = byUnit.get(at);
      if (first !== undefined) flags.fill(1, first, first + size);
      at = sig.indexOf(needle, at + 1);
    }
  }
  return flags;
}

function redactString(text, list) {
  const chars = Array.from(text);
  const { sig, where } = project(chars);
  const flags = cover(sig, list);
  if (!flags.includes(1)) return text;
  const out = [];
  let last = 0;
  for (let k = 0; k < flags.length; k++) {
    if (!flags[k]) continue;
    let j = k;
    while (j + 1 < flags.length && flags[j + 1]) j++;
    out.push(chars.slice(last, where[k]).join(''), MARKER);
    last = where[j] + 1;
    k = j;
  }
  out.push(chars.slice(last).join(''));
  return out.join('');
}

// Walks the entry rather than the serialized line, so a value carrying a quote is
// matched in its own form rather than in JSON's escaping of it.
function redact(entry, secrets) {
  const list = needles(secrets || values());
  if (list.length === 0) return entry;
  return walk(entry, list);
}

function walk(entry, list) {
  if (typeof entry === 'string') return redactString(entry, list);
  if (Array.isArray(entry)) return entry.map(item => walk(item, list));
  if (entry && typeof entry === 'object') {
    const out = {};
    for (const [key, value] of Object.entries(entry)) out[key] = walk(value, list);
    return out;
  }
  return entry;
}

module.exports = { redact, values, MARKER, LIST_PATH };
