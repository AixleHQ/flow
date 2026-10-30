// What Usage::TenantReport renders into the admin dashboard (keys camelized by
// Admin::DashboardsController): one row per company per UTC day, and the
// platform's size as it stands.

export type BillingClass =
  'not_metered' | 'inactive' | 'managed' | 'blocked' | 'trial' | 'unlimited' | 'no_customer' | 'paying';

export interface UsageDay {
  companyId: number;
  day: string;
  hours: number;
  offeredSeconds: number;
  occupiedSeconds: number;
  unlimitedSeconds: number;
  limitMin: number | null;
  limitMax: number | null;
  peakWorkers: number;
  sessionsQueued: number;
  sessionsAdmitted: number;
  waitSecondsTotal: number;
  waitSecondsMax: number;
  sessionsSucceeded: number;
  sessionsFailed: number;
  billingClass: BillingClass;
}

export interface Tenant {
  id: number;
  name: string;
}

export interface Snapshot {
  companies: number;
  members: number;
  projects: number;
}

export interface DashboardData {
  tenants: Tenant[];
  days: UsageDay[];
  measuredThrough: string | null;
  snapshot: Snapshot;
}

// What Admin::DashboardCompaniesController returns for one company over the
// dashboard's selected days (Usage::CompanyBreakdown). Waits are in seconds.

export interface WaitStats {
  waited: number;
  average: number | null;
  p50: number | null;
  p90: number | null;
  p95: number | null;
  p99: number | null;
  max: number | null;
  p95OfWaited: number | null;
}

export interface SessionWaits extends WaitStats {
  sessions: number;
  aheadAverage: number | null;
  aheadP95: number | null;
  aheadMax: number | null;
}

export interface RunWaits extends WaitStats {
  runs: number;
  averageSteps: number | null;
}

export interface Capacity {
  /** Hours in which the company had workers; zero when it had no limit. */
  offeredHours: number;
  /** Share of those hours with every worker busy at once. */
  timeAtCapacity: number | null;
  waited: number;
  waitedAtCapacity: number;
}

export interface ProjectQueue {
  id: number;
  name: string;
  limit: number;
  reserved: boolean;
  sessions: number;
  waited: number;
  p95: number | null;
  max: number | null;
  aheadMax: number;
}

export interface WaitDay {
  day: string;
  sessions: number;
  waited: number;
  p95: number | null;
}

export interface CompanyBreakdown {
  companyId: number;
  workerLimit: number | null;
  projectDefault: number;
  capacity: Capacity;
  waits: SessionWaits;
  runs: RunWaits;
  projects: ProjectQueue[];
  days: WaitDay[];
}

/** One company's p95 wait over a range, from Admin::DashboardCompaniesController#waits. */
export interface TenantWait {
  companyId: number;
  p95: number;
}
