import { describe, expect, it } from 'vitest';

import { searchDocs } from './searchIndex';

describe('searchDocs', () => {
  it('returns [] for empty or whitespace-only queries', () => {
    expect(searchDocs('')).toEqual([]);
    expect(searchDocs('   ')).toEqual([]);
  });

  it('matches case-insensitively across title/desc/section', () => {
    const results = searchDocs('WORKFLOW');
    expect(results.length).toBeGreaterThan(0);
    expect(results.every((r) => /workflow/i.test(`${r.title} ${r.desc} ${r.section}`))).toBe(true);
  });

  it('matches on the section name', () => {
    expect(searchDocs('reference').some((r) => r.slug === 'reference')).toBe(true);
  });

  it('returns no matches for nonsense', () => {
    expect(searchDocs('zzzqqq')).toEqual([]);
  });
});
