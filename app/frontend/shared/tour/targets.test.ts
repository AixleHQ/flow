import { describe, expect, it } from 'vitest';

import { CHAPTERS } from './steps';
import { TOUR_TARGETS } from './targets';

// The source of every component outside the tour itself. A target that no markup mentions any more
// is a step that would point at nothing after a redesign.
const sources = Object.entries(
  import.meta.glob<string>(['../../**/*.tsx', '!../../**/*.test.tsx', '!./**'], {
    query: '?raw',
    import: 'default',
    eager: true,
  }),
);

describe('tour targets', () => {
  it.each(TOUR_TARGETS)('"%s" is put on an element somewhere in the app', (target) => {
    const marked = new RegExp(`(tourTarget\\(|tour:\\s*|tour=\\{[^}]*?)'${target}'`);
    const users = sources.filter(([, source]) => marked.test(source)).map(([file]) => file);
    expect(users, `no component marks an element with tourTarget('${target}')`).not.toHaveLength(0);
  });

  it('every target is pointed at by a step', () => {
    const used = new Set(Object.values(CHAPTERS).flatMap((steps) => steps.map((step) => step.target)));
    expect(TOUR_TARGETS.filter((target) => !used.has(target))).toEqual([]);
  });
});
