import type { UsageDay } from 'pages/Admin/Dashboard/types';

// One tenant's whole UTC day at a steady two workers out of a limit of four, as
// Usage::TenantReport sends it.
export const buildUsageDay = (overrides: Partial<UsageDay> = {}): UsageDay => ({
  companyId: 1,
  day: '2026-10-14',
  hours: 24,
  offeredSeconds: 4 * 24 * 3600,
  occupiedSeconds: 2 * 24 * 3600,
  unlimitedSeconds: 0,
  limitMin: 4,
  limitMax: 4,
  peakWorkers: 3,
  sessionsQueued: 40,
  sessionsAdmitted: 40,
  waitSecondsTotal: 40 * 30,
  waitSecondsMax: 120,
  sessionsSucceeded: 38,
  sessionsFailed: 2,
  billingClass: 'paying',
  ...overrides,
});
