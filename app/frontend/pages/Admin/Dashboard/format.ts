import type { BillingClass } from './types';

const whole = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const tenths = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 });

/** Worker-hours: whole hours, with a tenth below ten so a light tenant does not read as zero. */
export const formatHours = (hours: number) => (hours < 10 ? tenths : whole).format(hours);

export const formatCount = (value: number) => whole.format(value);

export const formatWorkers = (value: number) => (Number.isFinite(value) ? whole.format(value) : '∞');

export const formatPercent = (ratio: number | null) => (ratio === null ? '—' : `${Math.round(ratio * 100)}%`);

export function formatWait(seconds: number | null): string {
  if (seconds === null) return '—';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const minutes = seconds / 60;
  if (minutes < 60) return `${tenths.format(minutes)} min`;
  return `${Math.floor(minutes / 60)}h ${Math.round(minutes % 60)}m`;
}

type Tone = 'success' | 'warning' | 'danger' | 'info';

export const BILLING_LABELS: Record<BillingClass, { label: string; tone: Tone }> = {
  paying: { label: 'Paying', tone: 'success' },
  no_customer: { label: 'Not billed · no Stripe customer', tone: 'danger' },
  unlimited: { label: 'Not billed · no limit', tone: 'danger' },
  managed: { label: 'Free · managed', tone: 'info' },
  trial: { label: 'Trial', tone: 'info' },
  blocked: { label: 'Blocked', tone: 'danger' },
  inactive: { label: 'Inactive', tone: 'warning' },
  not_metered: { label: 'Not metered', tone: 'info' },
};
