"""
Redaction of session secrets, applied where a log is WRITTEN rather than where it
is collected.

Every value an agent receives arrives through exactly one channel — the
`get_config_item` MCP tool — and that tool writes the value into this list before
it answers, so nothing can reach a log ahead of the list that hides it. The list
therefore only ever holds values the agent already has, which is why it needs no
special permissions: it tells the container nothing the container did not ask for.

Until now the scrubbing happened on the way out, in Sessions::SecretRedactor, which
meant the bytes had to travel through the application to be cleaned — and that, not
storage, is the reason log collection needs a size cap at all. Cleaning at the point
of writing is what lets a container ship its own logs later.

The file is one base64-encoded value per line: a secret may contain newlines, and
base64 keeps one value on one line whatever it holds.
"""
import base64
import os

LIST_PATH = os.environ.get("AIXLE_REDACT_LIST", "/var/log/mitm/redact.list")
MARKER = "<redacted:session-secret>"

_cache = {"key": None, "values": []}


def values():
    """Current secrets, longest first. Reloaded when the file changes.

    Longest-first so a secret that is a substring of a longer one never corrupts the
    longer replacement — the same ordering Sessions::SecretRedactor uses.
    """
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


def redact_bytes(raw, secrets=None):
    if not raw:
        return raw
    for secret in (values() if secrets is None else secrets):
        if secret in raw:
            raw = raw.replace(secret, MARKER.encode("utf-8"))
    return raw


def redact_text(text, secrets=None):
    if not isinstance(text, str) or not text:
        return text
    for secret in (values() if secrets is None else secrets):
        decoded = secret.decode("utf-8", "replace")
        if decoded and decoded in text:
            text = text.replace(decoded, MARKER)
    return text


def redact_obj(obj, secrets=None):
    """Walk a log entry and clean every string in it.

    Applied to the entry rather than to the serialized line, so a value carrying a
    quote or a backslash is matched in its own form rather than in JSON's escaping
    of it.
    """
    secrets = values() if secrets is None else secrets
    if not secrets:
        return obj
    if isinstance(obj, str):
        return redact_text(obj, secrets)
    if isinstance(obj, dict):
        return {key: redact_obj(value, secrets) for key, value in obj.items()}
    if isinstance(obj, list):
        return [redact_obj(item, secrets) for item in obj]
    return obj
