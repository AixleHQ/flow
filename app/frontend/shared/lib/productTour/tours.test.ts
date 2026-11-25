import { describe, expect, it } from 'vitest';

import { firstStepId, nextStepId, TOURS, type TourContext, type TourStep } from './tours';

// The tour finds its targets by `data-tour` attributes on ordinary components. A refactor that drops
// one breaks the tour without failing anything else, so every target and page a step names must exist.
const sources = import.meta.glob<string>(
  ['../../../pages/**/*.tsx', '../../ui/**/*.tsx', '../../components/**/*.tsx', '!**/*.test.tsx'],
  { query: '?raw', import: 'default', eager: true },
);

const pageFile = (component: string) => `../../../pages/${component}.tsx`;

// `template-card:<namespace>/<slug>` is built from the template it marks.
const anchorPattern = (key: string) => (key.startsWith('template-card:') ? 'template-card:' : `'${key}'|"${key}"`);

const ctx = (overrides: Partial<TourContext> = {}): TourContext => ({
  projectId: 1,
  runId: 2,
  runState: 'completed',
  runFinished: true,
  resumedFromToast: false,
  hasAgent: true,
  firstProjectId: 1,
  ...overrides,
});

describe('product tours', () => {
  const steps = Object.values(TOURS).flat();

  it.each(steps.filter((step) => step.page !== 'any'))('step $id is on a page that exists', (step) => {
    expect(Object.keys(sources)).toContain(pageFile(step.page));
  });

  it.each(steps.flatMap((step) => [step.target, step.clickTarget]).filter((key): key is string => Boolean(key)))(
    'target %s is rendered by some component',
    (key) => {
      const pattern = new RegExp(anchorPattern(key));
      expect(Object.values(sources).some((source) => pattern.test(source))).toBe(true);
    },
  );

  it('tour A goes from Templates to the closing words and B from Projects', () => {
    expect([firstStepId('a'), firstStepId('b')]).toEqual(['a1', 'b1']);

    const walk = (variant: 'a' | 'b', context: TourContext) => {
      const ids: string[] = [];
      let step: TourStep | undefined = TOURS[variant][0];
      while (step) {
        ids.push(step.id);
        const next = nextStepId(variant, step, context);
        step = TOURS[variant].find((candidate) => candidate.id === next);
      }
      return ids;
    };

    expect(walk('a', ctx())).toEqual(TOURS.a.map((step) => step.id));
    expect(walk('a', ctx({ runState: 'failed' })).slice(-2)).toEqual(['a13', 'a15']);
    expect(walk('a', ctx({ resumedFromToast: true })).slice(-2)).toEqual(['a13', 'a15']);
    expect(walk('a', ctx({ runState: 'running', runFinished: false })).slice(-3)).toEqual(['a13', 'a14', 'a15']);
    expect(walk('b', ctx())).toEqual(['b1', 'b2', 'b3', 'b4']);
    expect(walk('b', ctx({ firstProjectId: null }))).toEqual(['b1', 'b4']);
  });
});
