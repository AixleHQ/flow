import { describe, expect, it } from 'vitest';

import { isValidHttpsUrl } from './urlValidation';

describe('isValidHttpsUrl', () => {
  it('accepts https URLs (and trims surrounding whitespace)', () => {
    expect(isValidHttpsUrl('https://example.com')).toBe(true);
    expect(isValidHttpsUrl('  https://example.com/path?q=1  ')).toBe(true);
  });

  it('rejects non-https, empty, and malformed values', () => {
    expect(isValidHttpsUrl('http://example.com')).toBe(false);
    expect(isValidHttpsUrl('')).toBe(false);
    expect(isValidHttpsUrl('   ')).toBe(false);
    expect(isValidHttpsUrl('not a url')).toBe(false);
  });
});
