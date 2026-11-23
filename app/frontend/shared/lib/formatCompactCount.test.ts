import { describe, expect, it } from 'vitest';

import { formatCompactCount } from './formatCompactCount';

describe('formatCompactCount', () => {
  it('leaves values under a thousand as they are', () => {
    expect(formatCompactCount(0)).toBe('0');
    expect(formatCompactCount(999)).toBe('999');
  });

  it('abbreviates thousands, millions, billions and trillions', () => {
    expect(formatCompactCount(1_500)).toBe('1.5k');
    expect(formatCompactCount(2_500_000)).toBe('2.5M');
    expect(formatCompactCount(1_069_700_000)).toBe('1.1B');
    expect(formatCompactCount(3_200_000_000_000)).toBe('3.2T');
  });

  it('moves to the next unit when rounding reaches 1000', () => {
    expect(formatCompactCount(999_950)).toBe('1.0M');
    expect(formatCompactCount(999_950_000)).toBe('1.0B');
    expect(formatCompactCount(999_949)).toBe('999.9k');
  });

  it('uses the given thousands suffix', () => {
    expect(formatCompactCount(1_500, { thousandsSuffix: 'K' })).toBe('1.5K');
    expect(formatCompactCount(2_500_000, { thousandsSuffix: 'K' })).toBe('2.5M');
  });
});
