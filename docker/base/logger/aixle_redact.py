"""
Redaction of session secrets, applied where a log is WRITTEN rather than where it
is collected.

Every value an agent receives arrives through `get_config_item` or an MCP server's
header/env, and the platform writes the value into this list before handing it out,
so nothing can reach a log ahead of the list that hides it. The list therefore only
ever holds values the agent already has, which is why it needs no special
permissions: it tells the container nothing the container did not ask for.

The file is one base64-encoded value per line: a secret may contain newlines, and
base64 keeps one value on one line whatever it holds.

Matching is not a substring search, because a log rarely holds the value as one run
of characters. An agent's terminal draws it between colour codes and wraps it onto
the next row behind an indent — Claude Code 2.1.310 painted a 43-character key as
`pxk_l`, escape codes, `\\r`, a cursor move, spaces, `ive_7Hq…` — and a model streams
it to the proxy a few characters per event. So a text is first PROJECTED onto its
significant characters (escape sequences, whitespace, control and box-drawing
characters dropped) and the secret is looked for there. A secret of FRAGMENT_FLOOR
characters or more is also masked piece by piece — every FRAGMENT-character run of it
that mixes letter cases or letters and digits, wherever it appears — which is what still
catches a value split by a partial repaint or cut short by a size limit. A run without
that mix (`https://`, `services`, a vendor prefix like `sk_live_`) occurs everywhere and
says nothing about the secret, and a shorter secret is too likely to occur by chance in
pieces; those are only masked as part of the whole value.

Terminal streams are masked character for character with MASK, never with a marker:
the CLIs paint with absolute cursor moves, and text of a different width would shift
everything painted after it on that row.
"""
import base64
import codecs
import json
import os
import re
import sys
import unicodedata

LIST_PATH = os.environ.get("AIXLE_REDACT_LIST", "/var/log/mitm/redact.list")
MARKER = "<redacted:session-secret>"
MASK = "*"
FRAGMENT = 8
FRAGMENT_FLOOR = 16
# Leaves whose strings a streamed response spreads across events: Anthropic's text,
# partial_json and thinking deltas, OpenAI's delta / content / arguments, Gemini's text.
STREAMED_KEYS = frozenset({"text", "partial_json", "thinking", "delta", "content", "arguments"})
# An unterminated OSC would otherwise hold a stream back forever, or hide the rest of
# a text from the masking.
MAX_ESCAPE = 4096
# How many of a secret's pieces Needles.any_in checks; see there.
PROBES_PER_SECRET = 64

_cache = {"key": None, "values": []}


def values():
    """Current secrets, longest first. Reloaded when the file changes."""
    try:
        st = os.stat(LIST_PATH)
        key = (st.st_mtime_ns, st.st_size)
    except OSError:
        # No list yet is the normal state of a session that never read a secret.
        _cache["key"] = None
        _cache["values"] = []
        return []

    if _cache["key"] != key:
        loaded = []
        try:
            with open(LIST_PATH, "rb") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        value = base64.b64decode(line, validate=True)
                    except Exception:
                        continue
                    if value:
                        loaded.append(value)
        except OSError:
            return _cache["values"]

        loaded.sort(key=len, reverse=True)
        _cache["values"] = loaded
        _cache["key"] = key

    return _cache["values"]


def escape_end(text, i):
    """Index just past the escape sequence that starts at text[i], or None if it is cut off."""
    n = len(text)
    if i + 1 >= n:
        return None
    kind = text[i + 1]
    if kind == "[":
        j = i + 2
        while j < n:
            o = ord(text[j])
            if 0x40 <= o <= 0x7E:
                return j + 1
            if not 0x20 <= o <= 0x3F:
                return j
            j += 1
        return None
    if kind in "]PX^_":
        j = i + 2
        while j < n:
            if text[j] == "\x07":
                return j + 1
            if text[j] == "\x1b":
                if j + 1 >= n:
                    return None
                if text[j + 1] == "\\":
                    return j + 2
            j += 1
        return n if n - i > MAX_ESCAPE else None
    if kind in "()*+-./#%":
        return i + 3 if i + 2 < n else None
    return i + 2


# What a projection drops: a complete escape sequence, or a run of whitespace, control
# and box-drawing characters. One expression for both the quick check and the indexed
# projection, so the two cannot disagree about what is significant.
NOISE = re.compile(
    r"\x1b(?:\[[\x20-\x3f]*[\x40-\x7e]"
    r"|[\]PX^_](?:[^\x07\x1b]|\x1b(?!\\)){0," + str(MAX_ESCAPE) + r"}(?:\x07|\x1b\\)"
    r"|[()*+\-./#%].|[^\[\]PX^_()*+\-./#%])"
    r"|[\s\x00-\x1f\x7f-\x9f\u2500-\u259f]+",
    re.S,
)


def cutoff(text):
    """Start of an escape sequence the text ends in the middle of, or None."""
    i = text.rfind("\x1b", max(0, len(text) - MAX_ESCAPE))
    return i if i != -1 and escape_end(text, i) is None else None


def project(text):
    """(significant characters, their indexes in text, start of a cut-off trailing escape or None)."""
    cut = cutoff(text)
    body = text if cut is None else text[:cut]
    chars, where, pos = [], [], 0
    for m in NOISE.finditer(body):
        if m.start() > pos:
            chars.append(body[pos:m.start()])
            where.extend(range(pos, m.start()))
        pos = m.end()
    if pos < len(body):
        chars.append(body[pos:])
        where.extend(range(pos, len(body)))
    return "".join(chars), where, cut


def distinctive(piece):
    """Mixes at least two of lower case, upper case and digits."""
    return sum((any(c.islower() for c in piece), any(c.isupper() for c in piece),
                any(c.isdigit() for c in piece))) >= 2


def core(value):
    """A short secret without the punctuation at its ends, when enough is left to be told apart.

    A password like `Summer2024!` reaches a log with its `!` shell-escaped or JSON-encoded
    as often as not, and eleven of its twelve characters are the secret all the same."""
    stripped = re.sub(r"^[\W_]+|[\W_]+$", "", value)
    return [stripped] if stripped != value and len(stripped) >= FRAGMENT else []


def fragments(value):
    """The pieces of a secret masked on their own, in the order they occur in it."""
    if len(value) < FRAGMENT_FLOOR:
        return core(value)
    pieces = (value[i:i + FRAGMENT] for i in range(len(value) - FRAGMENT + 1))
    return list(dict.fromkeys(piece for piece in pieces if distinctive(piece)))


class Needles:
    """What to look for in a projection: every secret whole, and the distinctive pieces of a long one."""

    def __init__(self, secrets):
        found, probes = set(), set()
        for secret in secrets:
            text = secret.decode("utf-8", "replace") if isinstance(secret, bytes) else str(secret)
            # A JSON body or transcript holds a value carrying a quote or a backslash only
            # in its escaped form.
            for form in {text, json.dumps(text, ensure_ascii=False)[1:-1]}:
                sig = NOISE.sub("", form)
                if sig:
                    pieces = fragments(sig)
                    found.add(sig)
                    found.update(pieces)
                    probes.add(sig)
                    probes.update(pieces[::max(1, -(-len(pieces) // PROBES_PER_SECRET))])
        self.needles = sorted(found, key=len, reverse=True)
        self.probes = sorted(probes, key=len, reverse=True)
        # Significant characters a stream must hold back: the longest needle less one.
        self.hold = max((len(n) for n in self.needles), default=1) - 1

    def __bool__(self):
        return bool(self.needles)

    def any_in(self, text):
        """Whether text can hold anything to mask, decided without building the projection's
        index. A long secret (a PEM key, a service-account JSON) has hundreds of pieces, and
        this runs on every request body, so only an evenly spread sample of them is checked;
        a piece that falls between two samples is found only when it is longer than the gap."""
        sig = NOISE.sub("", text)
        return any(probe in sig for probe in self.probes)

    def cover(self, sig):
        """One flag per character of sig, set where a secret or a piece of one sits."""
        flags = bytearray(len(sig))
        for needle in self.needles:
            size = len(needle)
            start = sig.find(needle)
            while start != -1:
                flags[start:start + size] = b"\x01" * size
                start = sig.find(needle, start + 1)
        return flags


_needles_cache = {"key": None, "needles": Needles([])}


def needles(secrets=None):
    secrets = values() if secrets is None else secrets
    key = tuple(secrets)
    if _needles_cache["key"] != key:
        _needles_cache["needles"] = Needles(secrets)
        _needles_cache["key"] = key
    return _needles_cache["needles"]


def mask_char(ch):
    return MASK * 2 if unicodedata.east_asian_width(ch) in ("W", "F") else MASK


def mask_terminal(text, found=None):
    """A terminal stream with every secret character replaced in place, keeping the layout."""
    found = needles() if found is None else found
    if not found or not text or not found.any_in(text):
        return text
    sig, where, _ = project(text)
    flags = found.cover(sig)
    out = list(text)
    for k, flag in enumerate(flags):
        if flag:
            out[where[k]] = mask_char(out[where[k]])
    return "".join(out)


def mask_text(text, found=None):
    """A string with each run of secret characters replaced by MARKER."""
    found = needles() if found is None else found
    if not found or not isinstance(text, str) or not text or not found.any_in(text):
        return text
    sig, where, _ = project(text)
    flags = found.cover(sig)
    out, last, k, n = [], 0, 0, len(flags)
    while k < n:
        if not flags[k]:
            k += 1
            continue
        j = k
        while j + 1 < n and flags[j + 1]:
            j += 1
        out.append(text[last:where[k]])
        out.append(MARKER)
        last = where[j] + 1
        k = j + 1
    out.append(text[last:])
    return "".join(out)


def mask_binary(raw, secrets=None):
    """Raw bytes with every secret byte replaced by MASK, length unchanged so framing survives."""
    secrets = values() if secrets is None else secrets
    if not raw or not secrets:
        return raw
    out = None
    for secret in secrets:
        text = secret.decode("utf-8", "replace")
        parts = {secret} | {piece.encode("utf-8") for piece in fragments(text)}
        for part in parts:
            start = raw.find(part)
            while start != -1:
                if out is None:
                    out = bytearray(raw)
                out[start:start + len(part)] = MASK.encode() * len(part)
                start = raw.find(part, start + 1)
    return raw if out is None else bytes(out)


def redact_obj(obj, found=None):
    """Walk a log entry and mask every string in it."""
    found = needles() if found is None else found
    if not found:
        return obj
    if isinstance(obj, str):
        return mask_text(obj, found)
    if isinstance(obj, dict):
        return {key: redact_obj(value, found) for key, value in obj.items()}
    if isinstance(obj, list):
        return [redact_obj(item, found) for item in obj]
    return obj


def _streamed_leaves(obj, refs, key=None):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str):
                if k in STREAMED_KEYS:
                    refs.append((obj, k))
            else:
                _streamed_leaves(v, refs, k)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            if isinstance(v, str):
                if key in STREAMED_KEYS:
                    refs.append((obj, i))
            else:
                _streamed_leaves(v, refs, key)


def mask_streamed(docs, found):
    """Mask secrets a stream spread across the streamed strings of several documents, in place."""
    refs = []
    for doc in docs:
        _streamed_leaves(doc, refs)
    if not refs:
        return False
    pieces = [container[k] for container, k in refs]
    joined = "".join(pieces)
    if not found.any_in(joined):
        return False
    sig, where, _ = project(joined)
    flags = found.cover(sig)
    if 1 not in flags:
        return False
    chars = list(joined)
    for k, flag in enumerate(flags):
        if flag:
            chars[where[k]] = MASK
    pos = 0
    for (container, k), piece in zip(refs, pieces):
        container[k] = "".join(chars[pos:pos + len(piece)])
        pos += len(piece)
    return True


def mask_body(text, found=None):
    """A logged HTTP body. An event stream or a streamed JSON array has its streamed
    text reassembled before matching; anything else is matched as text."""
    found = needles() if found is None else found
    if not found or not text:
        return text
    head = text.lstrip()[:6]
    if head.startswith(("event:", "data:", "id:", ":")) or "\ndata:" in text:
        lines = text.split("\n")
        slots, docs = [], []
        for i, line in enumerate(lines):
            if line.startswith("data:"):
                try:
                    docs.append(json.loads(line[5:]))
                    slots.append(i)
                except ValueError:
                    pass
        if mask_streamed(docs, found):
            for i, doc in zip(slots, docs):
                lines[i] = "data: " + json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
            text = "\n".join(lines)
    elif head[:1] == "[":
        # A JSON array is how a stream arrives without SSE (one document per chunk); an
        # object is a request or a whole response, whose strings are never split.
        try:
            doc = json.loads(text)
        except ValueError:
            doc = None
        if doc is not None and mask_streamed([doc], found):
            text = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    # Whole strings — and their JSON-escaped forms — are found in the text itself.
    return mask_text(text, found)


class TerminalStream:
    """Masks a terminal byte stream as it passes through.

    Holds back only what a secret could still continue from: the last Needles.hold
    significant characters with whatever was painted after them, and an escape
    sequence cut off at the end of a read. A match can reach into characters that
    are held, never into characters already written, so the held text keeps its
    original characters and its mask flags separately.
    """

    MAX_HOLD = 65536

    def __init__(self, secrets_fn=values):
        self._secrets_fn = secrets_fn
        self._decoder = codecs.getincrementaldecoder("utf-8")("surrogateescape")
        self._text = ""
        self._flags = bytearray()

    def feed(self, data):
        return self._emit(self._decoder.decode(data), final=False)

    def flush(self):
        return self._emit(self._decoder.decode(b"", final=True), final=True)

    def _emit(self, more, final):
        text = self._text + more
        flags = self._flags + bytearray(len(more))
        found = needles(self._secrets_fn())
        if not text:
            return b""

        cut = len(text)
        if found:
            sig, where, cutoff = project(text)
            if found.any_in(text):
                for k, flag in enumerate(found.cover(sig)):
                    if flag:
                        flags[where[k]] = 1
            if not final:
                if cutoff is not None:
                    cut = cutoff
                held = min(found.hold, len(sig))
                if held:
                    cut = min(cut, where[len(sig) - held])
                if len(text) - cut > self.MAX_HOLD:
                    cut = len(text)

        out = "".join(mask_char(ch) if flags[i] else ch for i, ch in enumerate(text[:cut]))
        self._text, self._flags = text[cut:], flags[cut:]
        return out.encode("utf-8", "surrogateescape")


def redact_file(kind, src, dst):
    """Write a masked copy of a collected log. Returns the bytes written."""
    found = needles()
    with open(src, "rb") as handle:
        raw = handle.read()
    text = raw.decode("utf-8", "surrogateescape")
    if not found:
        out = text
    elif kind == "jsonl":
        lines = text.split("\n")
        for i, line in enumerate(lines):
            if line.strip() and found.any_in(line):
                lines[i] = mask_body(line, found)
        out = "\n".join(lines)
    else:
        out = mask_text(text, found)
    data = out.encode("utf-8", "surrogateescape")
    with open(dst, "wb") as handle:
        handle.write(data)
    return len(data)


if __name__ == "__main__":
    # python3 aixle_redact.py file <jsonl|text> <src> <dst>
    if len(sys.argv) == 5 and sys.argv[1] == "file":
        print(redact_file(sys.argv[2], sys.argv[3], sys.argv[4]))
    else:
        sys.exit("usage: aixle_redact.py file <jsonl|text> <src> <dst>")
