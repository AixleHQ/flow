import { describe, expect, it } from 'vitest';

import {
  calculateRoi,
  DEFAULT_ROI_INPUTS,
  formatMoney,
  formatMonths,
  formatPercent,
  irr,
  monthlyCostPerWorker,
  suggestedWorkers,
} from './roi';

describe('calculateRoi', () => {
  // Every number here is read off the "Workflow ROI" sheet of the Aixle Flow ROI
  // Calculator at its shipped inputs. This is the case that catches the page and
  // the spreadsheet drifting apart.
  it('reproduces the spreadsheet at its own inputs', () => {
    const roi = calculateRoi(DEFAULT_ROI_INPUTS);

    expect(roi.effectiveCostPerHour).toBeCloseTo(5, 10);
    expect(roi.breakevenHours).toBeCloseTo(1111.111111, 4);
    expect(roi.paybackMonths).toBeCloseTo(7.407407407, 6);
    expect(roi.aixleCost).toBe(86_000);
    expect(roi.humanCost).toBe(360_000);
    expect(roi.savings).toBe(274_000);
    expect(roi.roi).toBeCloseTo(3.186046512, 8);
    expect(roi.irr).toBeCloseTo(1.58364327, 7);
  });

  // B21:B31 — year 0 is the setup, then hours saved x (labour rate - effective
  // rate) for each year of the period.
  it('lays the cash flows out the way the sheet does', () => {
    expect(calculateRoi(DEFAULT_ROI_INPUTS).cashFlows).toEqual([-50_000, 81_000, 81_000, 81_000, 81_000]);
  });

  it('scales cost with the period and leaves setup alone', () => {
    const roi = calculateRoi({ ...DEFAULT_ROI_INPUTS, years: 1 });

    expect(roi.aixleCost).toBe(59_000);
    expect(roi.humanCost).toBe(90_000);
    expect(roi.cashFlows).toEqual([-50_000, 81_000]);
  });

  it('charges less per hour as the speed-up rises', () => {
    const fast = calculateRoi({ ...DEFAULT_ROI_INPUTS, acceleratorMultiple: 10 });

    expect(fast.effectiveCostPerHour).toBeCloseTo(0.5, 10);
    expect(fast.aixleCost).toBe(50_000 + 0.5 * 1800 * 4);
  });

  // The sheet's own table stops at ten years, so a longer period would be
  // discounting flows it has no row for.
  it('never runs the cash flows past the tenth year', () => {
    expect(calculateRoi({ ...DEFAULT_ROI_INPUTS, years: 25 }).cashFlows).toHaveLength(11);
  });

  // The page has free-text inputs, so a visitor can describe a deal that never
  // pays for itself. It has to say so rather than render NaN.
  it('never breaks even when a worker-hour costs more than an hour of labour', () => {
    const roi = calculateRoi({ ...DEFAULT_ROI_INPUTS, laborCostPerHour: 2 });

    expect(roi.breakevenHours).toBe(Infinity);
    expect(roi.paybackMonths).toBe(Infinity);
    expect(roi.roi).toBeLessThan(0);
    expect(roi.irr).toBeNull();
  });

  it('survives a zero speed-up and a zero period', () => {
    expect(calculateRoi({ ...DEFAULT_ROI_INPUTS, acceleratorMultiple: 0 }).irr).toBeNull();
    expect(calculateRoi({ ...DEFAULT_ROI_INPUTS, years: 0 }).irr).toBeNull();
  });
});

describe('irr', () => {
  it('finds the rate that discounts the flows to nothing', () => {
    expect(irr([-100, 110])).toBeCloseTo(0.1, 10);
    expect(irr([-1000, 500, 500, 500])).toBeCloseTo(0.23375, 5);
  });

  it('has no answer for flows that never turn positive', () => {
    expect(irr([-100, -100])).toBeNull();
    expect(irr([-100])).toBeNull();
  });
});

describe('worker sizing', () => {
  it('prices a worker at the list rate for every hour of the month', () => {
    expect(monthlyCostPerWorker(5)).toBe(3600);
  });

  it('suggests one worker for a workload that fits in one', () => {
    expect(suggestedWorkers(DEFAULT_ROI_INPUTS)).toBe(1);
  });

  it('adds workers as the workload outgrows them', () => {
    expect(suggestedWorkers({ hoursSavedPerYear: 18_000, acceleratorMultiple: 1 })).toBe(9);
  });
});

describe('formatting', () => {
  it('writes money, percentages and months the way the sheet does', () => {
    expect(formatMoney(86_000)).toBe('$86,000');
    expect(formatMoney(0.5, 2)).toBe('$0.50');
    expect(formatPercent(3.186046512)).toBe('318.60%');
    expect(formatMonths(7.407407407)).toBe('7.4 months');
  });

  it('says so plainly when there is no number to show', () => {
    expect(formatMoney(Infinity)).toBe('—');
    expect(formatMonths(Infinity)).toBe('never');
    expect(formatPercent(null)).toBe('—');
  });
});
