import { afterEach, describe, expect, it } from 'vitest';

import { inertiaState } from 'test/inertiaMock';
import { renderHook } from 'test/renderPage';

import { useFeatureFlag } from './useFeatureFlag';

const flag = 'externalRunners';

function readFlag() {
  return renderHook(() => useFeatureFlag(flag)).result.current;
}

describe('useFeatureFlag', () => {
  afterEach(() => {
    inertiaState.pageProps = {};
  });

  it('is true when the server resolved the flag on', () => {
    inertiaState.pageProps = { features: { externalRunners: true } };

    expect(readFlag()).toBe(true);
  });

  it('is false when the server resolved the flag off', () => {
    inertiaState.pageProps = { features: { externalRunners: false } };

    expect(readFlag()).toBe(false);
  });

  it('is false when the payload does not carry the flag', () => {
    inertiaState.pageProps = { features: { somethingElse: true } };

    expect(readFlag()).toBe(false);
  });

  it('is false when the page sends no features prop at all', () => {
    inertiaState.pageProps = {};

    expect(readFlag()).toBe(false);
  });

  it('only accepts declared flag names', () => {
    inertiaState.pageProps = { features: {} };

    // @ts-expect-error a misspelled flag name is a type error, which `yarn tsc` reports.
    expect(renderHook(() => useFeatureFlag('externalRuners')).result.current).toBe(false);
  });
});
