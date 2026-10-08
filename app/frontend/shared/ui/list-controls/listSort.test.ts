import { describe, expect, it } from 'vitest';

import { DEFAULT_LIST_SORT, formatListSort, isDefaultListSort, nextListSort, parseListSort } from './listSort';

describe('listSort', () => {
  it('reads ransack sort strings, defaulting to newest first', () => {
    expect(parseListSort('cost_cents asc')).toEqual({ field: 'cost_cents', direction: 'asc' });
    expect(parseListSort('duration_seconds')).toEqual({ field: 'duration_seconds', direction: 'desc' });
    expect(parseListSort(undefined)).toEqual(DEFAULT_LIST_SORT);
    expect(isDefaultListSort(parseListSort(''))).toBe(true);
  });

  it('starts a new column highest-first and flips the active one', () => {
    const byCost = nextListSort(DEFAULT_LIST_SORT, 'cost_cents');
    expect(formatListSort(byCost)).toBe('cost_cents desc');
    expect(formatListSort(nextListSort(byCost, 'cost_cents'))).toBe('cost_cents asc');
    expect(formatListSort(nextListSort(DEFAULT_LIST_SORT, 'created_at'))).toBe('created_at asc');
  });
});
