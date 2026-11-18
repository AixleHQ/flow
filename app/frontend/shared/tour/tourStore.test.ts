import { beforeEach, describe, expect, it } from 'vitest';

import { readOffer, readTourState, shouldOffer, updateOffer, writeTourState } from './tourStore';

describe('tour offer', () => {
  beforeEach(() => {
    localStorage.clear();
    sessionStorage.clear();
  });

  it('is offered to someone who has not answered yet', () => {
    expect(shouldOffer(readOffer(1))).toBe(true);
  });

  it('comes back after one "Not now" and stops after the second', () => {
    updateOffer(1, { notNowCount: 1 });
    expect(shouldOffer(readOffer(1))).toBe(true);
    updateOffer(1, { notNowCount: 2 });
    expect(shouldOffer(readOffer(1))).toBe(false);
  });

  it('stops for good once refused or finished', () => {
    updateOffer(1, { dismissed: true });
    updateOffer(2, { completed: true });
    expect(shouldOffer(readOffer(1))).toBe(false);
    expect(shouldOffer(readOffer(2))).toBe(false);
  });

  it('is remembered per user', () => {
    updateOffer(1, { dismissed: true });
    expect(shouldOffer(readOffer(2))).toBe(true);
  });
});

describe('tour state', () => {
  it('survives a page load and clears', () => {
    writeTourState({ chapter: 'first-run', stepId: 'A5' });
    expect(readTourState()).toEqual({ chapter: 'first-run', stepId: 'A5' });
    writeTourState(null);
    expect(readTourState()).toBeNull();
  });
});
