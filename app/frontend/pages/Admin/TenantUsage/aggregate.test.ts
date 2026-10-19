import { describe, expect, it } from 'vitest';

import { buildUsageDay } from 'test/factories/tenantUsage';

import { comparisonRange, deltaOf, mondayOf, periodsFor, rangeOf, summarize } from './aggregate';

const tenants = [{ id: 1, name: 'Acme' }];

describe('periods', () => {
  it('starts weeks on Monday', () => {
    expect(mondayOf('2026-10-19')).toBe('2026-10-19');
    expect(mondayOf('2026-10-18')).toBe('2026-10-12');
  });

  it('spans a whole calendar month', () => {
    expect(rangeOf('month', '2026-02')).toEqual({ start: '2026-02-01', end: '2026-02-28' });
  });

  it('lists the periods that have data, newest first', () => {
    const days = ['2026-09-30', '2026-10-01', '2026-10-14'].map((day) => buildUsageDay({ day }));

    expect(periodsFor('month', days)).toEqual(['2026-10', '2026-09']);
    expect(periodsFor('week', days)).toEqual(['2026-10-12', '2026-09-28']);
  });
});

describe('comparisonRange', () => {
  it('compares a finished month with the whole month before', () => {
    expect(comparisonRange('month', rangeOf('month', '2026-09'), '2026-09-30')).toEqual({
      start: '2026-08-01',
      end: '2026-08-31',
    });
  });

  it('compares a month in progress with the same number of days of the one before', () => {
    expect(comparisonRange('month', rangeOf('month', '2026-10'), '2026-10-19')).toEqual({
      start: '2026-09-01',
      end: '2026-09-19',
    });
  });

  it('never runs past the end of a shorter previous month', () => {
    expect(comparisonRange('month', rangeOf('month', '2026-03'), '2026-03-30')).toEqual({
      start: '2026-02-01',
      end: '2026-02-28',
    });
  });

  it('compares a week in progress with the same days of the week before', () => {
    expect(comparisonRange('week', rangeOf('week', '2026-10-19'), '2026-10-21')).toEqual({
      start: '2026-10-12',
      end: '2026-10-14',
    });
  });

  it('compares a custom range with the same number of days just before it', () => {
    expect(comparisonRange('custom', { start: '2026-10-10', end: '2026-10-14' }, '2026-10-19')).toEqual({
      start: '2026-10-05',
      end: '2026-10-09',
    });
  });
});

describe('summarize', () => {
  it('sums a tenant across its days', () => {
    const days = [
      buildUsageDay({ day: '2026-10-13', limitMin: 2, limitMax: 4, peakWorkers: 4, waitSecondsMax: 300 }),
      buildUsageDay({ day: '2026-10-14', billingClass: 'no_customer' }),
      buildUsageDay({ day: '2026-10-20' }),
    ];

    const [acme] = summarize(days, tenants, { start: '2026-10-01', end: '2026-10-14' });

    expect(acme).toMatchObject({
      name: 'Acme',
      workerHours: 192,
      busyHours: 96,
      utilization: 0.5,
      minWorkers: 2,
      maxWorkers: 4,
      peakWorkers: 4,
      avgWaitSeconds: 30,
      maxWaitSeconds: 300,
      sessionsSucceeded: 76,
      sessionsFailed: 4,
      billingClass: 'no_customer',
    });
  });

  it('has no utilization and no maximum limit for a tenant without a limit', () => {
    const days = [
      buildUsageDay({
        offeredSeconds: 0,
        unlimitedSeconds: 24 * 3600,
        limitMin: null,
        limitMax: null,
        billingClass: 'unlimited',
      }),
    ];

    const [acme] = summarize(days, tenants, { start: '2026-10-14', end: '2026-10-14' });

    expect(acme.utilization).toBeNull();
    expect(acme.maxWorkers).toBe(Infinity);
    expect(acme.busyHours).toBe(48);
  });

  it('has no wait for a tenant that admitted nothing', () => {
    const days = [buildUsageDay({ sessionsAdmitted: 0, waitSecondsTotal: 0, waitSecondsMax: 0 })];

    const [acme] = summarize(days, tenants, { start: '2026-10-14', end: '2026-10-14' });

    expect(acme.avgWaitSeconds).toBeNull();
    expect(acme.maxWaitSeconds).toBeNull();
  });
});

describe('deltaOf', () => {
  it('reports utilization in points and marks a rise as better', () => {
    expect(deltaOf('utilization', 0.62, 0.5)).toEqual({ text: '▲ +12 pts', tone: 'good' });
  });

  it('marks a longer wait and more failures as worse', () => {
    expect(deltaOf('avgWaitSeconds', 90, 60)).toEqual({ text: '▲ +50%', tone: 'bad' });
    expect(deltaOf('sessionsFailed', 1, 4)).toEqual({ text: '▼ −75%', tone: 'good' });
  });

  it('gives hours no better direction', () => {
    expect(deltaOf('workerHours', 50, 100)).toEqual({ text: '▼ −50%', tone: 'neutral' });
  });

  it('counts workers rather than taking a percentage', () => {
    expect(deltaOf('peakWorkers', 5, 3)).toEqual({ text: '▲ +2', tone: 'neutral' });
    expect(deltaOf('maxWorkers', 3, 3)).toEqual({ text: 'no change', tone: 'neutral' });
  });

  it('calls growth from nothing new, and has nothing to say without a figure on both sides', () => {
    expect(deltaOf('sessionsSucceeded', 4, 0)).toEqual({ text: 'new', tone: 'neutral' });
    expect(deltaOf('utilization', null, 0.5)).toBeNull();
    expect(deltaOf('maxWorkers', Infinity, 4)).toBeNull();
  });
});
