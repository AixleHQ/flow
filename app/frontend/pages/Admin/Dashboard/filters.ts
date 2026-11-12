import type { TenantSummary } from './aggregate';
import type { AccountStatus, AccountType, BillingMethod } from './types';

export const NO_BILLING_METHOD = 'none';

export type BillingMethodChoice = BillingMethod | typeof NO_BILLING_METHOD;

export interface Filters {
  query: string;
  statuses: AccountStatus[];
  types: AccountType[];
  methods: BillingMethodChoice[];
  /** UTC days as YYYY-MM-DD; an empty one leaves that end open. */
  createdFrom: string;
  createdTo: string;
}

export const NO_FILTERS: Filters = {
  query: '',
  statuses: [],
  types: [],
  methods: [],
  createdFrom: '',
  createdTo: '',
};

/** Whether any account filter is set; the name search is not one of them. */
export const hasAccountFilters = (filters: Filters) =>
  filters.statuses.length > 0 ||
  filters.types.length > 0 ||
  filters.methods.length > 0 ||
  Boolean(filters.createdFrom || filters.createdTo);

export const isFiltered = (filters: Filters) => hasAccountFilters(filters) || filters.query.trim() !== '';

const among = <T>(chosen: T[], value: T | null) => !chosen.length || (value !== null && chosen.includes(value));

/** Whether a company passes every filter set: any of the values chosen for a field, and every field. */
export function matches(row: TenantSummary, filters: Filters): boolean {
  const needle = filters.query.trim().toLowerCase();
  if (needle && !row.name.toLowerCase().includes(needle)) return false;
  if (!among(filters.statuses, row.accountStatus)) return false;
  if (!among(filters.types, row.accountType)) return false;
  if (!among<BillingMethodChoice>(filters.methods, row.billingMethod ?? NO_BILLING_METHOD)) return false;

  let { createdFrom: from, createdTo: to } = filters;
  if (from && to && from > to) [from, to] = [to, from];
  if (!from && !to) return true;
  const day = row.createdAt?.slice(0, 10);
  if (!day) return false;
  return (!from || day >= from) && (!to || day <= to);
}

export const filterRows = (rows: TenantSummary[], filters: Filters) => rows.filter((row) => matches(row, filters));
