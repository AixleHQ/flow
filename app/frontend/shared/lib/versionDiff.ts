// Compares two entity version snapshots field by field, driven by a per-type
// schema (versionSchemas.ts). Snapshots arrive with their stored snake_case
// keys — they hold file paths and header names, so the API sends them verbatim.

export type Snapshot = Record<string, unknown>;

/** Display names for the resource ids a workflow snapshot mentions, by model then id. */
export type References = Record<string, Record<string, { name: string; archived: boolean }>>;

export type FieldSpec =
  | { kind: 'scalar'; key: string; label: string }
  | { kind: 'text'; key: string; label: string }
  | { kind: 'json'; key: string; label: string }
  | { kind: 'list'; key: string; label: string }
  | { kind: 'refs'; key: string; label: string; model: string }
  | { kind: 'ref'; key: string; label: string; model: string }
  | { kind: 'stepRefs'; key: string; label: string }
  | { kind: 'textMap'; key: string; label: string }
  | { kind: 'secretMap'; key: string; label: string }
  | { kind: 'collection'; key: string; label: string; itemKey: string; itemLabel: string; fields: FieldSpec[] };

export type DiffLine = { type: 'same' | 'added' | 'removed'; text: string };

export type RefItem = { id: string; name: string; archived: boolean; missing: boolean };

export type Change =
  | { kind: 'scalar'; label: string; before: unknown; after: unknown }
  | { kind: 'text'; label: string; lines: DiffLine[] | null }
  | { kind: 'list'; label: string; added: string[]; removed: string[] }
  | { kind: 'refs'; label: string; added: RefItem[]; removed: RefItem[] }
  | { kind: 'entries'; label: string; entries: EntryChange[] }
  | { kind: 'collection'; label: string; items: ItemChange[] };

export type EntryChange = { name: string; status: 'added' | 'removed' | 'changed'; lines?: DiffLine[] | null };

export type ItemChange = {
  label: string;
  status: 'added' | 'removed' | 'changed' | 'moved';
  changes: Change[];
};

/** Past this many lines a side, a text diff is not computed: the change is reported without its lines. */
export const MAX_DIFF_LINES = 2000;

export function getPath(source: unknown, path: string): unknown {
  return path.split('.').reduce<unknown>((value, part) => {
    if (value && typeof value === 'object') return (value as Record<string, unknown>)[part];
    return undefined;
  }, source);
}

/** Line diff by longest common subsequence; null when either side is too long to diff. */
// CRLF and LF are the same text here, and a final newline ends the last line
// rather than starting an empty one.
const toLines = (text: string) => {
  const normalized = text.replace(/\r\n/g, '\n').replace(/\n$/, '');
  return normalized === '' ? [] : normalized.split('\n');
};

export function diffLines(before: string, after: string): DiffLine[] | null {
  const a = toLines(before);
  const b = toLines(after);
  if (a.length > MAX_DIFF_LINES || b.length > MAX_DIFF_LINES) return null;

  const table: number[][] = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i -= 1) {
    for (let j = b.length - 1; j >= 0; j -= 1) {
      table[i][j] = a[i] === b[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    }
  }

  const lines: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      lines.push({ type: 'same', text: a[i] });
      i += 1;
      j += 1;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      lines.push({ type: 'removed', text: a[i] });
      i += 1;
    } else {
      lines.push({ type: 'added', text: b[j] });
      j += 1;
    }
  }
  while (i < a.length) lines.push({ type: 'removed', text: a[i++] });
  while (j < b.length) lines.push({ type: 'added', text: b[j++] });
  return lines;
}

function asText(value: unknown): string {
  if (value === null || value === undefined) return '';
  return typeof value === 'string' ? value.replace(/\r\n/g, '\n') : JSON.stringify(value);
}

function asJson(value: unknown): string {
  if (value === null || value === undefined) return '';
  return JSON.stringify(value, null, 2);
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

// Absent, null, false, 0-length and '' all mean "not set": a snapshot taken
// before a key existed must not read as a change to its default.
function blank(value: unknown): boolean {
  if (value === null || value === undefined || value === false || value === '') return true;
  if (Array.isArray(value)) return value.length === 0;
  return typeof value === 'object' && Object.keys(value).length === 0;
}

function same(a: unknown, b: unknown): boolean {
  if (blank(a) && blank(b)) return true;
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
}

function refItem(model: string, id: string, references: References): RefItem {
  const found = references[model]?.[id];
  return { id, name: found?.name ?? `#${id}`, archived: found?.archived ?? false, missing: !found };
}

interface Context {
  references: References;
  stepNames: Map<string, string>;
}

function diffField(spec: FieldSpec, before: unknown, after: unknown, ctx: Context): Change | null {
  switch (spec.kind) {
    case 'scalar':
      return same(before, after) ? null : { kind: 'scalar', label: spec.label, before, after };
    case 'text':
    case 'json': {
      const render = spec.kind === 'json' ? asJson : asText;
      if (same(before, after)) return null;
      const [a, b] = [render(blank(before) ? null : before), render(blank(after) ? null : after)];
      return a === b ? null : { kind: 'text', label: spec.label, lines: diffLines(a, b) };
    }
    case 'list': {
      const a = asArray(before).map(String);
      const b = asArray(after).map(String);
      const added = b.filter((x) => !a.includes(x));
      const removed = a.filter((x) => !b.includes(x));
      if (added.length || removed.length) return { kind: 'list', label: spec.label, added, removed };
      return same(a, b) ? null : { kind: 'list', label: `${spec.label} (order)`, added: [], removed: [] };
    }
    case 'refs':
    case 'ref':
    case 'stepRefs': {
      const ids = (value: unknown) =>
        (spec.kind === 'ref' ? [value].filter((v) => v !== null && v !== undefined) : asArray(value)).map(String);
      const a = ids(before);
      const b = ids(after);
      const toItem = (id: string): RefItem =>
        spec.kind === 'stepRefs'
          ? { id, name: ctx.stepNames.get(id) ?? `#${id}`, archived: false, missing: !ctx.stepNames.has(id) }
          : refItem(spec.model, id, ctx.references);
      const added = b.filter((x) => !a.includes(x)).map(toItem);
      const removed = a.filter((x) => !b.includes(x)).map(toItem);
      return added.length || removed.length ? { kind: 'refs', label: spec.label, added, removed } : null;
    }
    case 'textMap':
    case 'secretMap': {
      const a = asRecord(before);
      const b = asRecord(after);
      const names = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
      const entries: EntryChange[] = [];
      for (const name of names) {
        if (!(name in a)) entries.push({ name, status: 'added' });
        else if (!(name in b)) entries.push({ name, status: 'removed' });
        else if (asText(a[name]) !== asText(b[name])) {
          entries.push(
            spec.kind === 'textMap'
              ? { name, status: 'changed', lines: diffLines(asText(a[name]), asText(b[name])) }
              : { name, status: 'changed' },
          );
        }
      }
      return entries.length ? { kind: 'entries', label: spec.label, entries } : null;
    }
    case 'collection':
      return diffCollection(spec, before, after, ctx);
  }
}

const SUBSTANTIVE = new Set<Change['kind']>(['text', 'refs', 'entries', 'collection']);

function diffCollection(
  spec: Extract<FieldSpec, { kind: 'collection' }>,
  before: unknown,
  after: unknown,
  ctx: Context,
): Change | null {
  const keyOf = (item: unknown) => String(asRecord(item)[spec.itemKey]);
  const labelOf = (item: unknown) => asText(asRecord(item)[spec.itemLabel]) || keyOf(item);
  const a = asArray(before);
  const b = asArray(after);
  const beforeByKey = new Map(a.map((item) => [keyOf(item), item]));
  const afterKeys = new Set(b.map(keyOf));
  const beforeOrder = a.map(keyOf).filter((key) => afterKeys.has(key));
  const afterOrder = b.map(keyOf).filter((key) => beforeByKey.has(key));

  const items: ItemChange[] = [];
  for (const item of b) {
    const key = keyOf(item);
    const previous = beforeByKey.get(key);
    if (previous === undefined) {
      // A new item's settings are its defaults: only what was written into it is worth listing.
      const changes = diffFields(spec.fields, {}, item, ctx).filter((c) => SUBSTANTIVE.has(c.kind));
      items.push({ label: labelOf(item), status: 'added', changes });
      continue;
    }
    const changes = diffFields(spec.fields, previous, item, ctx);
    const moved = beforeOrder.indexOf(key) !== afterOrder.indexOf(key);
    if (changes.length) items.push({ label: labelOf(item), status: 'changed', changes });
    else if (moved) items.push({ label: labelOf(item), status: 'moved', changes: [] });
  }
  for (const item of a) {
    if (!afterKeys.has(keyOf(item))) items.push({ label: labelOf(item), status: 'removed', changes: [] });
  }
  return items.length ? { kind: 'collection', label: spec.label, items } : null;
}

function diffFields(fields: FieldSpec[], before: unknown, after: unknown, ctx: Context): Change[] {
  return fields
    .map((spec) => diffField(spec, getPath(before, spec.key), getPath(after, spec.key), ctx))
    .filter((change): change is Change => change !== null);
}

function stepNames(...snapshots: (Snapshot | null)[]): Map<string, string> {
  const names = new Map<string, string>();
  for (const snapshot of snapshots) {
    for (const step of asArray(snapshot?.steps)) {
      const record = asRecord(step);
      names.set(String(record.id), asText(record.name));
    }
  }
  return names;
}

/** Every change from `before` to `after`. A null `before` (the first version) diffs against an empty entity. */
export function diffSnapshots(
  schema: FieldSpec[],
  before: Snapshot | null,
  after: Snapshot,
  references: References = {},
): Change[] {
  const ctx = { references, stepNames: stepNames(before, after) };
  return diffFields(schema, before ?? {}, after, ctx);
}
