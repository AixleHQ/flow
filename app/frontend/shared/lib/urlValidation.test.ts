import { describe, expect, it } from 'vitest';

import { isValidHttpUrl } from './urlValidation';

describe('isValidHttpUrl', () => {
  it('accepts http and https URLs (and trims surrounding whitespace)', () => {
    expect(isValidHttpUrl('http://example.com')).toBe(true);
    expect(isValidHttpUrl('https://example.com')).toBe(true);
    expect(isValidHttpUrl('  https://example.com/path?q=1  ')).toBe(true);
  });

  it('rejects non-http(s), empty, and malformed values', () => {
    expect(isValidHttpUrl('ftp://example.com')).toBe(false);
    expect(isValidHttpUrl('')).toBe(false);
    expect(isValidHttpUrl('   ')).toBe(false);
    expect(isValidHttpUrl('not a url')).toBe(false);
  });
});
