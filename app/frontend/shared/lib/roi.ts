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
  /** B6 — list price of one queue-hour. */
  queueHourlyRate: number;
  /** B7 — how many times faster Flow runs the process. */
  acceleratorMultiple: number;
  /** B13 — analysis period. */
  years: number;
}

export interface RoiResult {
  /** B8 — queue price divided by the speed-up, for an apples-to-apples hour. */
  effectiveCostPerHour: number;
  /** B10 — hours of saving needed to pay the setup back. */
  breakevenHours: number;
  /** B11 — the same, in months. Infinite when Flow costs more than the people. */
  breakevenMonths: number;
  /** B14 — setup plus queue time over the whole period. */
  aixleCost: number;
  /** B15 — what the same work costs in people over the whole period. */
  humanCost: number;
  /** Money left over. Not a spreadsheet cell; the page leads with it. */
  savings: number;
  /** B16 — return over the whole period. */
  totalRoi: number;
  /** B17 — see the note on annualizedRoi() below. */
  annualizedRoi: number;
}

/** A queue is a reserved slot, billed for every hour of the month it exists. */
export const HOURS_PER_QUEUE_MONTH = 720;

export const DEFAULT_ROI_INPUTS: RoiInputs = {
  hoursSavedPerYear: 1800,
  laborCostPerHour: 50,
  setupCost: 50_000,
  queueHourlyRate: 5,
  acceleratorMultiple: 10,
  years: 3,
};

// B17 is `POWER(totalRoi, 1/years)`, which is not an annualised return — that
// would be `(1 + totalRoi) ^ (1/years) - 1`, and on the default inputs the two
// differ by more than double (160% against 72%). The spreadsheet's figure is
// already in circulation with customers, so it is reproduced exactly rather than
// quietly corrected here; correcting it is a sales decision, not a code one.
const annualizedRoi = (totalRoi: number, years: number): number =>
  totalRoi <= 0 || years <= 0 ? 0 : Math.pow(totalRoi, 1 / years);

export function calculateRoi(inputs: RoiInputs): RoiResult {
  const { hoursSavedPerYear, laborCostPerHour, setupCost, queueHourlyRate, acceleratorMultiple, years } = inputs;

  const effectiveCostPerHour = acceleratorMultiple > 0 ? queueHourlyRate / acceleratorMultiple : Infinity;
  const savedPerHour = laborCostPerHour - effectiveCostPerHour;

  // Flow costing more per hour than the people it replaces never pays the setup
  // back, however long you wait.
  const breakevenHours = savedPerHour > 0 ? setupCost / savedPerHour : Infinity;
  const breakevenMonths = hoursSavedPerYear > 0 ? (breakevenHours / hoursSavedPerYear) * 12 : Infinity;

  const aixleCost = setupCost + effectiveCostPerHour * hoursSavedPerYear * years;
  const humanCost = laborCostPerHour * hoursSavedPerYear * years;
  // A zero speed-up puts an infinite cost on both sides of the division, which
  // is NaN rather than the total loss it plainly is.
  const totalRoi = Number.isFinite(aixleCost) && aixleCost > 0 ? (humanCost - aixleCost) / aixleCost : -1;

  return {
    effectiveCostPerHour,
    breakevenHours,
    breakevenMonths,
    aixleCost,
    humanCost,
    savings: humanCost - aixleCost,
    totalRoi,
    annualizedRoi: annualizedRoi(totalRoi, years),
  };
}

/** What a queue costs to keep open for a month, at list price. */
export const monthlyCostPerQueue = (queueHourlyRate: number): number => queueHourlyRate * HOURS_PER_QUEUE_MONTH;

/**
 * Queue-hours the workflow actually consumes in a month. A queue runs one
 * session at a time, so this is what decides how many a workspace needs.
 */
export const queueHoursPerMonth = (inputs: Pick<RoiInputs, 'hoursSavedPerYear' | 'acceleratorMultiple'>): number =>
  inputs.acceleratorMultiple > 0 ? inputs.hoursSavedPerYear / inputs.acceleratorMultiple / 12 : Infinity;

/**
 * Queues to reserve for that load. Utilisation is never 100% — work arrives in
 * bursts — so the demand is taken against a busy quarter of the month rather
 * than against all 720 hours, and never rounds below one.
 */
export const suggestedQueues = (inputs: Pick<RoiInputs, 'hoursSavedPerYear' | 'acceleratorMultiple'>): number => {
  const hours = queueHoursPerMonth(inputs);
  if (!Number.isFinite(hours)) return 1;
  return Math.max(1, Math.ceil(hours / (HOURS_PER_QUEUE_MONTH * 0.25)));
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

export const formatPercent = (ratio: number): string => (Number.isFinite(ratio) ? `${(ratio * 100).toFixed(2)}%` : '—');

export const formatMonths = (value: number): string =>
  Number.isFinite(value) ? `${value.toFixed(1)} months` : 'never';
