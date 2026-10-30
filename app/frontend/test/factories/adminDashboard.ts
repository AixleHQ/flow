import type { CompanyBreakdown, UsageDay } from 'pages/Admin/Dashboard/types';

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

// A company with a limit of two whose queue backed up in a few busy stretches, as
// Usage::CompanyBreakdown sends it.
export const buildCompanyBreakdown = (overrides: Partial<CompanyBreakdown> = {}): CompanyBreakdown => ({
  companyId: 1,
  workerLimit: 2,
  projectDefault: 4,
  capacity: { offeredHours: 720, timeAtCapacity: 0.06, waited: 80, waitedAtCapacity: 76 },
  waits: {
    sessions: 400,
    waited: 80,
    average: 95,
    p50: 0,
    p90: 340,
    p95: 600,
    p99: 1_500,
    max: 4_800,
    p95OfWaited: 1_400,
    aheadAverage: 0.3,
    aheadP95: 2,
    aheadMax: 9,
  },
  runs: {
    runs: 300,
    averageSteps: 1.3,
    waited: 70,
    average: 120,
    p50: 0,
    p90: 420,
    p95: 700,
    p99: 2_000,
    max: 6_000,
    p95OfWaited: 1_800,
  },
  projects: [
    {
      id: 7,
      name: 'Support desk',
      limit: 1,
      reserved: true,
      sessions: 300,
      waited: 75,
      p95: 900,
      max: 4_800,
      aheadMax: 9,
    },
    { id: 8, name: 'Docs', limit: 4, reserved: false, sessions: 100, waited: 5, p95: 40, max: 200, aheadMax: 1 },
  ],
  days: [
    { day: '2026-10-13', sessions: 12, waited: 0, p95: 4 },
    { day: '2026-10-14', sessions: 230, waited: 51, p95: 7_260 },
    { day: '2026-10-15', sessions: 170, waited: 29, p95: 840 },
  ],
  ...overrides,
});
