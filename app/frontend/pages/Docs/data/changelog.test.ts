import { describe, expect, it } from 'vitest';

import { changeTone, entriesByArea, entriesMarkdown, formatReleaseDate, isUnreleased } from './changelog';

describe('Docs/data/changelog', () => {
  it('gathers entries under their area in first-seen order, area-less ones last', () => {
    const groups = entriesByArea([
      { area: null, text: 'licence' },
      { area: 'Tasks', text: 'a' },
      { area: 'Workflows', text: 'b' },
      { area: 'Tasks', text: 'c' },
    ]);

    expect(groups.map((g) => g.area)).toEqual(['Tasks', 'Workflows', null]);
    expect(groups[0].entries.map((e) => e.text)).toEqual(['a', 'c']);
    expect(groups[2].entries.map((e) => e.text)).toEqual(['licence']);
  });

  it('writes entries as a markdown list, each starting with a capital', () => {
    expect(
      entriesMarkdown([
        { area: 'Tasks', text: 'subtasks on the board' },
        { area: 'Tasks', text: '`/api-docs` behind auth' },
      ]),
    ).toBe('- Subtasks on the board\n- `/api-docs` behind auth');
  });

  it('formats a release date in full, whatever the reader’s time zone', () => {
    expect(formatReleaseDate('2026-10-08')).toBe('October 8, 2026');
    expect(formatReleaseDate('soon')).toBe('soon');
  });

  it('tones each Keep a Changelog kind', () => {
    expect(changeTone('Added')).toBe('success');
    expect(changeTone('Fixed')).toBe('tip');
    expect(changeTone('Removed')).toBe('danger');
    expect(changeTone('Whatever')).toBe('neutral');
  });

  it('recognises the unreleased section', () => {
    const release = { date: null, url: null, summary: '', changes: [] };
    expect(isUnreleased({ ...release, version: 'Unreleased' })).toBe(true);
    expect(isUnreleased({ ...release, version: '1.0.0' })).toBe(false);
  });
});
