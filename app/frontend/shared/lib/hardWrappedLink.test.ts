import { describe, expect, it } from 'vitest';

import { findHardWrappedLink } from './hardWrappedLink';

function buffer(rows: string[]) {
  return [(line: number) => rows[line - 1] ?? '', rows.length] as const;
}

describe('findHardWrappedLink', () => {
  const rows = [
    'Browser did not open? Use the url below to sign in:',
    '',
    'https://claude.ai/oauth/authorize?code=true&client_id=9d1c',
    '250a-e61b-44d9-88ed-5944d1962f5e&state=abc',
    '',
    'Paste code here if prompted >',
  ];

  it('rejoins a URL the CLI hard-wrapped across rows, from any of its rows', () => {
    const expected = {
      url: 'https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&state=abc',
      start: { x: 1, y: 3 },
      end: { x: 42, y: 4 },
    };

    expect(findHardWrappedLink(3, ...buffer(rows))).toEqual(expected);
    expect(findHardWrappedLink(4, ...buffer(rows))).toEqual(expected);
  });

  it('starts the link after prose on its first row', () => {
    const cursor = ['Open a browser and navigate to this link: https://cursor.com/login?c=ab', 'cd12&x=1', ''];

    expect(findHardWrappedLink(2, ...buffer(cursor))).toEqual({
      url: 'https://cursor.com/login?c=abcd12&x=1',
      start: { x: 43, y: 1 },
      end: { x: 8, y: 2 },
    });
  });

  it('finds nothing on rows without a URL', () => {
    expect(findHardWrappedLink(1, ...buffer(rows))).toBeNull();
    expect(findHardWrappedLink(6, ...buffer(rows))).toBeNull();
    expect(findHardWrappedLink(1, ...buffer(['standalone']))).toBeNull();
  });

  it('does not claim a bare word above a URL as part of the link', () => {
    const lines = ['done', 'https://example.com/a'];

    expect(findHardWrappedLink(1, ...buffer(lines))).toBeNull();
    expect(findHardWrappedLink(2, ...buffer(lines))?.url).toBe('https://example.com/a');
  });
});
