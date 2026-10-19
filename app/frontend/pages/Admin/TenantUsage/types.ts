// The daily rows Usage::TenantReport renders into the page (keys camelized by
// Admin::TenantUsagesController). One row per company per UTC day.

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

export interface TenantUsageData {
  tenants: Tenant[];
  days: UsageDay[];
  measuredThrough: string | null;
}
