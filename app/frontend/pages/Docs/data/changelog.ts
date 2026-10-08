export interface ChangelogEntry {
  area: string | null;
  text: string;
}

export interface ChangelogChange {
  kind: string;
  note: string | null;
  entries: ChangelogEntry[];
}

export interface ChangelogRelease {
  version: string;
  date: string | null;
  url: string | null;
  summary: string;
  changes: ChangelogChange[];
}

export interface AreaGroup {
  area: string | null;
  entries: ChangelogEntry[];
}

export type ChangeTone = 'success' | 'info' | 'tip' | 'warning' | 'danger' | 'neutral';

const TONES: Record<string, ChangeTone> = {
  added: 'success',
  changed: 'info',
  fixed: 'tip',
  deprecated: 'warning',
  removed: 'danger',
  security: 'danger',
};

export function changeTone(kind: string): ChangeTone {
  return TONES[kind.toLowerCase()] ?? 'neutral';
}

export function isUnreleased(release: ChangelogRelease): boolean {
  return release.version.toLowerCase() === 'unreleased';
}

/**
 * Entries gathered under their product area, areas in the order they first
 * appear. Entries with no area — the repository-level ones — come last.
 */
export function entriesByArea(entries: ChangelogEntry[]): AreaGroup[] {
  const groups = new Map<string | null, ChangelogEntry[]>();
  entries.forEach((entry) => {
    const group = groups.get(entry.area);
    if (group) group.push(entry);
    else groups.set(entry.area, [entry]);
  });
  const named = [...groups].filter(([area]) => area !== null);
  const unnamed = groups.get(null);
  return [
    ...named.map(([area, grouped]) => ({ area, entries: grouped })),
    ...(unnamed ? [{ area: null, entries: unnamed }] : []),
  ];
}

/**
 * A markdown list of the entries. With the area moved into a heading, an entry
 * reads as a sentence on its own, so it starts with a capital.
 */
export function entriesMarkdown(entries: ChangelogEntry[]): string {
  return entries.map(({ text }) => `- ${text.replace(/^[a-z]/, (c) => c.toUpperCase())}`).join('\n');
}

const RELEASE_DATE = new Intl.DateTimeFormat('en-US', { dateStyle: 'long', timeZone: 'UTC' });

export function formatReleaseDate(date: string): string {
  const parsed = new Date(`${date}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) ? date : RELEASE_DATE.format(parsed);
}
