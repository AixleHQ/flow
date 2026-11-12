import { describe, expect, it } from 'vitest';

import { buildTenant, buildUsageDay } from 'test/factories/adminDashboard';

import { summarize } from './aggregate';
import { filterRows, hasAccountFilters, isFiltered, NO_FILTERS, type Filters } from './filters';
import type { Tenant } from './types';

const tenants: Tenant[] = [
  buildTenant({ id: 1, name: 'Acme', createdAt: '2026-03-09T22:15:00Z' }),
  buildTenant({
    id: 2,
    name: 'Globex',
    createdAt: '2026-10-02T08:00:00Z',
    accountStatus: 'trial_active',
    accountType: 'managed',
    billingMethod: null,
  }),
  buildTenant({
    id: 3,
    name: 'Initech',
    createdAt: '2026-10-31T23:59:59Z',
    accountStatus: 'trial_expired',
    billingMethod: 'saas_aws_marketplace',
  }),
];

const rows = summarize(
  tenants.map((tenant) => buildUsageDay({ companyId: tenant.id })),
  tenants,
  { start: '2026-10-14', end: '2026-10-14' },
);

const namesFor = (filters: Partial<Filters>) =>
  filterRows(rows, { ...NO_FILTERS, ...filters })
    .map((row) => row.name)
    .sort();

describe('filterRows', () => {
  it('keeps every company when nothing is set', () => {
    expect(namesFor({})).toEqual(['Acme', 'Globex', 'Initech']);
  });

  it('keeps a company with any of the values chosen for a field', () => {
    expect(namesFor({ statuses: ['trial_active', 'trial_expired'] })).toEqual(['Globex', 'Initech']);
    expect(namesFor({ types: ['managed'] })).toEqual(['Globex']);
  });

  it('matches a company nobody invoices by its missing billing method', () => {
    expect(namesFor({ methods: ['none'] })).toEqual(['Globex']);
    expect(namesFor({ methods: ['saas_stripe', 'saas_aws_marketplace'] })).toEqual(['Acme', 'Initech']);
  });

  it('keeps only a company that passes every field', () => {
    expect(namesFor({ types: ['paid'], statuses: ['trial_expired'] })).toEqual(['Initech']);
    expect(namesFor({ types: ['paid'], query: 'acm' })).toEqual(['Acme']);
  });

  it('takes the creation range by UTC day, both ends included, either end open', () => {
    expect(namesFor({ createdFrom: '2026-10-02', createdTo: '2026-10-31' })).toEqual(['Globex', 'Initech']);
    expect(namesFor({ createdFrom: '2026-10-03' })).toEqual(['Initech']);
    expect(namesFor({ createdTo: '2026-03-09' })).toEqual(['Acme']);
  });

  it('reads a creation range entered backwards the right way round', () => {
    expect(namesFor({ createdFrom: '2026-10-31', createdTo: '2026-10-02' })).toEqual(['Globex', 'Initech']);
  });

  it('leaves out a company the report sent no tenant for once an account filter is set', () => {
    const unknown = summarize([buildUsageDay({ companyId: 9 })], tenants, { start: '2026-10-14', end: '2026-10-14' });
    const filtered = (filters: Partial<Filters>) => filterRows(unknown, { ...NO_FILTERS, ...filters });

    expect(filtered({})).toHaveLength(1);
    expect(filtered({ statuses: ['active_customer'] })).toHaveLength(0);
    expect(filtered({ createdFrom: '2026-01-01' })).toHaveLength(0);
  });
});

describe('isFiltered', () => {
  it('counts an account filter or a name search, not a blank one', () => {
    expect(hasAccountFilters({ ...NO_FILTERS, query: 'acme' })).toBe(false);
    expect(hasAccountFilters({ ...NO_FILTERS, createdTo: '2026-10-31' })).toBe(true);
    expect(isFiltered({ ...NO_FILTERS, query: ' ' })).toBe(false);
    expect(isFiltered({ ...NO_FILTERS, query: 'acme' })).toBe(true);
    expect(isFiltered({ ...NO_FILTERS, statuses: ['canceled'] })).toBe(true);
  });
});
