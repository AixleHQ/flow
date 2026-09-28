import { describe, expect, it } from 'vitest';

import {
  calculateRoi,
  DEFAULT_ROI_INPUTS,
  formatMoney,
  formatMonths,
  formatPercent,
  monthlyCostPerQueue,
  suggestedQueues,
} from './roi';

describe('calculateRoi', () => {
  // Every number here is read off the "Workflow ROI" sheet of the Aixle Flow ROI
  // Calculator at its shipped inputs. This is the case that catches the page and
  // the spreadsheet drifting apart.
  it('reproduces the spreadsheet at its own inputs', () => {
    const roi = calculateRoi(DEFAULT_ROI_INPUTS);

    expect(roi.effectiveCostPerHour).toBeCloseTo(0.5, 10);
    expect(roi.breakevenHours).toBeCloseTo(1010.10101, 4);
    expect(roi.breakevenMonths).toBeCloseTo(6.734006734, 6);
    expect(roi.aixleCost).toBe(52_700);
    expect(roi.humanCost).toBe(270_000);
    expect(roi.savings).toBe(217_300);
    expect(roi.totalRoi).toBeCloseTo(4.123339658, 8);
    expect(roi.annualizedRoi).toBeCloseTo(1.60355196, 7);
  });

  it('scales cost with the period and leaves setup alone', () => {
    const roi = calculateRoi({ ...DEFAULT_ROI_INPUTS, years: 1 });

    expect(roi.aixleCost).toBe(50_900);
    expect(roi.humanCost).toBe(90_000);
  });

  it('charges more per hour as the speed-up falls', () => {
    const slow = calculateRoi({ ...DEFAULT_ROI_INPUTS, acceleratorMultiple: 2 });

    expect(slow.effectiveCostPerHour).toBeCloseTo(2.5, 10);
    expect(slow.aixleCost).toBe(50_000 + 2.5 * 1800 * 3);
  });

  // The page has free-text inputs, so a visitor can describe a deal that never
  // pays for itself. It has to say so rather than render NaN.
  it('never breaks even when a queue-hour costs more than an hour of labour', () => {
    const roi = calculateRoi({ ...DEFAULT_ROI_INPUTS, laborCostPerHour: 0.25 });

    expect(roi.breakevenHours).toBe(Infinity);
    expect(roi.breakevenMonths).toBe(Infinity);
    expect(roi.totalRoi).toBeLessThan(0);
    expect(roi.annualizedRoi).toBe(0);
  });

  it('survives a zero speed-up and a zero period', () => {
    expect(calculateRoi({ ...DEFAULT_ROI_INPUTS, acceleratorMultiple: 0 }).annualizedRoi).toBe(0);
    expect(calculateRoi({ ...DEFAULT_ROI_INPUTS, years: 0 }).annualizedRoi).toBe(0);
  });
});

describe('queue sizing', () => {
  it('prices a queue at the list rate for every hour of the month', () => {
    expect(monthlyCostPerQueue(5)).toBe(3600);
  });

  it('suggests one queue for a workload that fits in one', () => {
    expect(suggestedQueues(DEFAULT_ROI_INPUTS)).toBe(1);
  });

  it('adds queues as the workload outgrows them', () => {
    expect(suggestedQueues({ hoursSavedPerYear: 180_000, acceleratorMultiple: 10 })).toBe(9);
  });
});

describe('formatting', () => {
  it('writes money, percentages and months the way the sheet does', () => {
    expect(formatMoney(52_700)).toBe('$52,700');
    expect(formatMoney(0.5, 2)).toBe('$0.50');
    expect(formatPercent(4.123339658)).toBe('412.33%');
    expect(formatMonths(6.734006734)).toBe('6.7 months');
  });

  it('says so plainly when there is no number to show', () => {
    expect(formatMoney(Infinity)).toBe('—');
    expect(formatMonths(Infinity)).toBe('never');
  });
});
