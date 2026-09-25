import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import './zodConfig';

describe('zod configuration', () => {
  it('validates without the eval-based JIT the CSP reports', () => {
    expect(z.config().jitless).toBe(true);
  });
});
