import { afterEach, describe, expect, it } from 'vitest';

import { companyMembershipPath, companyProjectBoardPath, userPath } from '@/shared/routes';

import { currentCompanySlug } from './currentCompanySlug';

describe('company links', () => {
  afterEach(() => window.history.pushState({}, '', '/'));

  it('stay in the company the tab is on', () => {
    window.history.pushState({}, '', '/company/acme/projects/7/board');

    expect(currentCompanySlug()).toBe('acme');
    expect(companyProjectBoardPath(7, { n: 3 })).toBe('/company/acme/projects/7/board?n=3');
    expect(userPath(5)).toBe('/company/acme/user/5');
  });

  it('name another company when asked to', () => {
    window.history.pushState({}, '', '/company/acme/projects');

    expect(companyProjectBoardPath(7, { company_slug: 'globex' })).toBe('/company/globex/projects/7/board');
  });

  it('leave the company out on a page of no company, for the server to fill in', () => {
    window.history.pushState({}, '', '/profile');

    expect(currentCompanySlug()).toBeNull();
    expect(companyProjectBoardPath(7)).toBe('/company/projects/7/board');
    expect(companyMembershipPath(3)).toBe('/company/memberships/3');
  });
});
