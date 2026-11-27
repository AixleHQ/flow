import { describe, expect, it } from 'vitest';

import { truncateText } from './truncateText';

describe('truncateText', () => {
  it('returns text shorter than the limit unchanged', () => {
    expect(truncateText('short', 10)).toBe('short');
    expect(truncateText('', 10)).toBe('');
  });

  it('returns text of exactly the limit unchanged', () => {
    expect(truncateText('abcde', 5)).toBe('abcde');
  });

  it('cuts text one character over the limit and adds an ellipsis', () => {
    expect(truncateText('abcdef', 5)).toBe('abcde…');
  });

  it('does not split an emoji at the boundary', () => {
    expect(truncateText('ab😀cd', 3)).toBe('ab😀…');
  });

  it('drops whitespace before the ellipsis', () => {
    expect(truncateText('abc   def', 5)).toBe('abc…');
  });
});
