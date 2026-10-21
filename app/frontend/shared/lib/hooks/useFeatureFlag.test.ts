import { afterEach, describe, expect, it } from 'vitest';

import type { FeatureFlagName } from '@/types/generated/featureFlags';
import { inertiaState } from 'test/inertiaMock';
import { renderHook } from 'test/renderPage';

import { useFeatureFlag } from './useFeatureFlag';

// The shipped registry declares no client flag, so FeatureFlagName is `never` until one exists.
// The name is widened and narrowed back so this test keeps compiling whatever gets declared.
const flag = 'boardAiSummary' as string as FeatureFlagName;

function readFlag() {
  return renderHook(() => useFeatureFlag(flag)).result.current;
}

describe('useFeatureFlag', () => {
  afterEach(() => {
    inertiaState.pageProps = {};
  });

  it('is true when the server resolved the flag on', () => {
    inertiaState.pageProps = { features: { boardAiSummary: true } };

    expect(readFlag()).toBe(true);
  });

  it('is false when the server resolved the flag off', () => {
    inertiaState.pageProps = { features: { boardAiSummary: false } };

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
    expect(renderHook(() => useFeatureFlag('boardAiSumary')).result.current).toBe(false);
  });
});
