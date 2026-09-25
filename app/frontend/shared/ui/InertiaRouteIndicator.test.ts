import { describe, expect, it } from 'vitest';

import { isNavigation } from './InertiaRouteIndicator';

const visit = (overrides = {}) => ({
  only: [] as string[],
  except: [] as string[],
  async: false,
  prefetch: false,
  showProgress: true,
  ...overrides,
});

describe('InertiaRouteIndicator', () => {
  it('shows for a visit to another page', () => {
    expect(isNavigation(visit())).toBe(true);
  });

  it('stays hidden while the page refreshes part of itself or prefetches', () => {
    expect(isNavigation(visit({ only: ['tasks'] }))).toBe(false);
    expect(isNavigation(visit({ except: ['flash'] }))).toBe(false);
    expect(isNavigation(visit({ async: true }))).toBe(false);
    expect(isNavigation(visit({ prefetch: true }))).toBe(false);
    expect(isNavigation(visit({ showProgress: false }))).toBe(false);
  });
});
