import type { BillingClass, Tenant, UsageDay } from './types';

// Days are UTC calendar days written as YYYY-MM-DD; weeks start on Monday.

export type Grain = 'day' | 'week' | 'month' | 'custom';

export interface DayRange {
  start: string;
  end: string;
}

export interface TenantSummary {
  tenantId: number;
  name: string;
  firstDay: string;
  lastDay: string;
  workerHours: number;
  busyHours: number;
  minWorkers: number;
  maxWorkers: number;
  peakWorkers: number;
  utilization: number | null;
  avgWaitSeconds: number | null;
  maxWaitSeconds: number | null;
  sessionsSucceeded: number;
  sessionsFailed: number;
  billingClass: BillingClass;
}

export interface Totals {
  workerHours: number;
  busyHours: number;
  sessionsSucceeded: number;
  sessionsFailed: number;
}

const DAY_MS = 86_400_000;

const toTime = (day: string) => Date.parse(`${day}T00:00:00Z`);
const toDay = (time: number) => new Date(time).toISOString().slice(0, 10);

export const todayOf = (now: Date) => toDay(now.getTime());
export const addDays = (day: string, count: number) => toDay(toTime(day) + count * DAY_MS);
export const daysBetween = (from: string, to: string) => Math.round((toTime(to) - toTime(from)) / DAY_MS);
export const mondayOf = (day: string) => addDays(day, -((new Date(toTime(day)).getUTCDay() + 6) % 7));

const lastDayOfMonth = (month: string) => {
  const [year, index] = month.split('-').map(Number);
  return toDay(Date.UTC(year, index, 0));
};

const previousMonth = (month: string) => {
  const [year, index] = month.split('-').map(Number);
  return toDay(Date.UTC(year, index - 2, 1)).slice(0, 7);
};

const minDay = (a: string, b: string) => (a < b ? a : b);

export function periodOf(grain: Exclude<Grain, 'custom'>, day: string): string {
  if (grain === 'week') return mondayOf(day);
  if (grain === 'month') return day.slice(0, 7);
  return day;
}

export function rangeOf(grain: Exclude<Grain, 'custom'>, period: string): DayRange {
  if (grain === 'week') return { start: period, end: addDays(period, 6) };
  if (grain === 'month') return { start: `${period}-01`, end: lastDayOfMonth(period) };
  return { start: period, end: period };
}

/** Every period that has data, newest first. */
export function periodsFor(grain: Exclude<Grain, 'custom'>, days: UsageDay[]): string[] {
  return Array.from(new Set(days.map((row) => periodOf(grain, row.day))))
    .sort()
    .reverse();
}

/**
 * The stretch a period is compared with. A period still under way is compared
 * with the same number of days of the one before, so a half-finished month is
 * not set against a whole one.
 */
export function comparisonRange(grain: Grain, range: DayRange, dataEnd: string): DayRange | null {
  if (grain === 'day') {
    const previous = addDays(range.start, -1);
    return { start: previous, end: previous };
  }
  const effectiveEnd = minDay(range.end, dataEnd);
  if (effectiveEnd < range.start) return null;

  if (grain === 'month') {
    const start = `${previousMonth(range.start.slice(0, 7))}-01`;
    const fullEnd = addDays(range.start, -1);
    if (dataEnd >= range.end) return { start, end: fullEnd };
    return { start, end: minDay(addDays(start, daysBetween(range.start, effectiveEnd)), fullEnd) };
  }

  const length = daysBetween(range.start, effectiveEnd);
  const start = grain === 'week' ? addDays(range.start, -7) : addDays(range.start, -1 - length);
  return { start, end: addDays(start, length) };
}

export function summarize(days: UsageDay[], tenants: Tenant[], range: DayRange): TenantSummary[] {
  const names = new Map(tenants.map((tenant) => [tenant.id, tenant.name]));
  const byTenant = new Map<number, UsageDay[]>();
  for (const row of days) {
    if (row.day < range.start || row.day > range.end) continue;
    const rows = byTenant.get(row.companyId) ?? [];
    rows.push(row);
    byTenant.set(row.companyId, rows);
  }

  return Array.from(byTenant, ([tenantId, rows]) => {
    rows.sort((a, b) => a.day.localeCompare(b.day));
    const sum = (pick: (row: UsageDay) => number) => rows.reduce((total, row) => total + pick(row), 0);
    const offered = sum((row) => row.offeredSeconds);
    const admitted = sum((row) => row.sessionsAdmitted);
    const bounded = rows.flatMap((row) => (row.limitMin === null ? [] : [row.limitMin]));
    const maxima = rows.flatMap((row) => (row.limitMax === null ? [] : [row.limitMax]));
    const everUnlimited = rows.some((row) => row.unlimitedSeconds > 0);

    return {
      tenantId,
      name: names.get(tenantId) ?? `Company #${tenantId}`,
      firstDay: rows[0].day,
      lastDay: rows[rows.length - 1].day,
      workerHours: offered / 3600,
      busyHours: sum((row) => row.occupiedSeconds) / 3600,
      minWorkers: bounded.length ? Math.min(...bounded) : Infinity,
      maxWorkers: everUnlimited || !maxima.length ? Infinity : Math.max(...maxima),
      peakWorkers: Math.max(...rows.map((row) => row.peakWorkers)),
      utilization: offered > 0 ? sum((row) => row.occupiedSeconds) / offered : null,
      avgWaitSeconds: admitted > 0 ? sum((row) => row.waitSecondsTotal) / admitted : null,
      maxWaitSeconds: admitted > 0 ? Math.max(...rows.map((row) => row.waitSecondsMax)) : null,
      sessionsSucceeded: sum((row) => row.sessionsSucceeded),
      sessionsFailed: sum((row) => row.sessionsFailed),
      billingClass: rows[rows.length - 1].billingClass,
    };
  });
}

export function totalsOf(rows: TenantSummary[]): Totals | null {
  if (!rows.length) return null;
  const sum = (pick: (row: TenantSummary) => number) => rows.reduce((total, row) => total + pick(row), 0);
  return {
    workerHours: sum((row) => row.workerHours),
    busyHours: sum((row) => row.busyHours),
    sessionsSucceeded: sum((row) => row.sessionsSucceeded),
    sessionsFailed: sum((row) => row.sessionsFailed),
  };
}

export type DeltaField =
  | 'workerHours'
  | 'busyHours'
  | 'minWorkers'
  | 'maxWorkers'
  | 'peakWorkers'
  | 'utilization'
  | 'avgWaitSeconds'
  | 'maxWaitSeconds'
  | 'sessionsSucceeded'
  | 'sessionsFailed';

export interface Delta {
  text: string;
  tone: 'good' | 'bad' | 'neutral';
}

// Which way is better. Hours and limits have no better direction: more of
// either is neither good nor bad on its own.
const BETTER: Partial<Record<DeltaField, 1 | -1>> = {
  utilization: 1,
  avgWaitSeconds: -1,
  maxWaitSeconds: -1,
  sessionsSucceeded: 1,
  sessionsFailed: -1,
};

const WORKER_FIELDS: DeltaField[] = ['minWorkers', 'maxWorkers', 'peakWorkers'];

const signed = (value: number, unit: string) =>
  value > 0 ? `▲ +${value}${unit}` : value < 0 ? `▼ −${Math.abs(value)}${unit}` : `0${unit}`;

/** The change from the previous period: points for utilization, a count for workers, a percentage otherwise. */
export function deltaOf(field: DeltaField, current: number | null, previous: number | null): Delta | null {
  if (current === null || previous === null || !Number.isFinite(current) || !Number.isFinite(previous)) return null;

  let change: number;
  let text: string;
  if (field === 'utilization') {
    change = Math.round((current - previous) * 100);
    text = signed(change, ' pts');
  } else if (WORKER_FIELDS.includes(field)) {
    change = current - previous;
    text = change === 0 ? 'no change' : signed(change, '');
  } else if (previous === 0) {
    return { text: current === 0 ? '0%' : 'new', tone: 'neutral' };
  } else {
    change = Math.round(((current - previous) / previous) * 100);
    text = signed(change, '%');
  }

  const better = BETTER[field];
  const tone = better && change !== 0 ? (change * better > 0 ? 'good' : 'bad') : 'neutral';
  return { text, tone };
}
