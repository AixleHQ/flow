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
