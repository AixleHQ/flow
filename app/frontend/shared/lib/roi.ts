// The sales ROI model, ported cell for cell from the "Workflow ROI" sheet of the
// Aixle Flow ROI Calculator. The page and the spreadsheet are quoted at the same
// customers in the same week, so they must not disagree: change one, change both.

export interface RoiInputs {
  /** B2 — labour hours the workflow takes off people each year. */
  hoursSavedPerYear: number;
  /** B3 — fully loaded cost of one of those hours. */
  laborCostPerHour: number;
  /** B5 — one-off cost of setting Flow up and building the workflows. */
  setupCost: number;
  /** B6 — list price of one worker-hour. */
  workerHourlyRate: number;
  /** B7 — how many times faster Flow runs the process. */
  acceleratorMultiple: number;
  /** B13 — analysis period. */
  years: number;
}

export interface RoiResult {
  /** B8 — worker price divided by the speed-up, for an apples-to-apples hour. */
  effectiveCostPerHour: number;
  /** B10 — hours of saving needed to pay the setup back. */
  breakevenHours: number;
  /** B11 — the same, in months. Infinite when Flow costs more than the people. */
  paybackMonths: number;
  /** B14 — setup plus worker time over the whole period. */
  aixleCost: number;
  /** B15 — what the same work costs in people over the whole period. */
  humanCost: number;
  /** Money left over. Not a spreadsheet cell; the page leads with it. */
  savings: number;
  /** B16 — return over the whole period. */
  roi: number;
  /** B17 — IRR of the cash flows below. Null when they never turn positive. */
  irr: number | null;
  /** B21:B31 — year 0 is the setup, then one entry per year of the period. */
  cashFlows: number[];
}

/** A worker is reserved capacity, billed for every hour of the month it exists. */
export const HOURS_PER_WORKER_MONTH = 720;

/** B21:B31 — the sheet's cash-flow table is ten years long. */
export const MAX_YEARS = 10;

/** D17 — the band the sheet tells a customer to judge the IRR against. */
export const IRR_BENCHMARK = { low: 0.15, high: 0.25 };

export const DEFAULT_ROI_INPUTS: RoiInputs = {
  hoursSavedPerYear: 1800,
  laborCostPerHour: 50,
  setupCost: 50_000,
  workerHourlyRate: 5,
  acceleratorMultiple: 1,
  years: 4,
};

/**
 * Excel's IRR by bisection: the rate at which the flows discount to nothing.
 *
 * Newton's method is what a spreadsheet uses and what it is criticised for — it
 * walks off a flat region and reports #NUM on inputs that plainly have an
 * answer. These series are one negative followed by equal positives, where the
 * function is monotonic and bracketing always converges.
 */
export function irr(cashFlows: number[]): number | null {
  const npv = (rate: number) => cashFlows.reduce((sum, flow, year) => sum + flow / Math.pow(1 + rate, year), 0);

  // Just above -100%, where the later years are discounted into meaninglessness
  // and only year 0 is left, up to a rate no real deal reaches.
  let low = -0.999999;
  let high = 1e6;
  if (npv(low) <= 0 || npv(high) >= 0) return null;

  for (let i = 0; i < 200; i += 1) {
    const mid = (low + high) / 2;
    if (npv(mid) > 0) low = mid;
    else high = mid;
  }
  return (low + high) / 2;
}

export function calculateRoi(inputs: RoiInputs): RoiResult {
  const { hoursSavedPerYear, laborCostPerHour, setupCost, workerHourlyRate, acceleratorMultiple, years } = inputs;

  const effectiveCostPerHour = acceleratorMultiple > 0 ? workerHourlyRate / acceleratorMultiple : Infinity;
  const savedPerHour = laborCostPerHour - effectiveCostPerHour;

  // Flow costing more per hour than the people it replaces never pays the setup
  // back, however long you wait.
  const breakevenHours = savedPerHour > 0 ? setupCost / savedPerHour : Infinity;
  const paybackMonths = hoursSavedPerYear > 0 ? (breakevenHours / hoursSavedPerYear) * 12 : Infinity;

  const aixleCost = setupCost + effectiveCostPerHour * hoursSavedPerYear * years;
  const humanCost = laborCostPerHour * hoursSavedPerYear * years;
  // A zero speed-up puts an infinite cost on both sides of the division, which
  // is NaN rather than the total loss it plainly is.
  const roi = Number.isFinite(aixleCost) && aixleCost > 0 ? (humanCost - aixleCost) / aixleCost : -1;

  const periods = Math.max(0, Math.min(Math.floor(years), MAX_YEARS));
  const annualSaving = Number.isFinite(savedPerHour) ? hoursSavedPerYear * savedPerHour : 0;
  const cashFlows = [-setupCost, ...Array.from({ length: periods }, () => annualSaving)];

  return {
    effectiveCostPerHour,
    breakevenHours,
    paybackMonths,
    aixleCost,
    humanCost,
    savings: humanCost - aixleCost,
    roi,
    irr: irr(cashFlows),
    cashFlows,
  };
}

/** What a worker costs to keep for a month, at list price. */
export const monthlyCostPerWorker = (workerHourlyRate: number): number => workerHourlyRate * HOURS_PER_WORKER_MONTH;

/**
 * Worker-hours the workflow actually consumes in a month. A worker runs one
 * session at a time, so this is what decides how many a workspace needs.
 */
export const workerHoursPerMonth = (inputs: Pick<RoiInputs, 'hoursSavedPerYear' | 'acceleratorMultiple'>): number =>
  inputs.acceleratorMultiple > 0 ? inputs.hoursSavedPerYear / inputs.acceleratorMultiple / 12 : Infinity;

/**
 * Workers to reserve for that load. Utilisation is never 100% — work arrives in
 * bursts — so the demand is taken against a busy quarter of the month rather
 * than against all 720 hours, and never rounds below one.
 */
export const suggestedWorkers = (inputs: Pick<RoiInputs, 'hoursSavedPerYear' | 'acceleratorMultiple'>): number => {
  const hours = workerHoursPerMonth(inputs);
  if (!Number.isFinite(hours)) return 1;
  return Math.max(1, Math.ceil(hours / (HOURS_PER_WORKER_MONTH * 0.25)));
};

const money = (fractionDigits: number) =>
  new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  });

export const formatMoney = (value: number, fractionDigits = 0): string =>
  Number.isFinite(value) ? money(fractionDigits).format(value) : '—';

export const formatPercent = (ratio: number | null): string =>
  ratio != null && Number.isFinite(ratio) ? `${(ratio * 100).toFixed(2)}%` : '—';

export const formatMonths = (value: number): string =>
  Number.isFinite(value) ? `${value.toFixed(1)} months` : 'never';
