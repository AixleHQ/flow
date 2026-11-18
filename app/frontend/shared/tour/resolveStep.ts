import { CHAPTERS, type TourChapter, type TourContext, type TourStep } from './steps';

export const stepsFor = (chapter: TourChapter, ctx: TourContext) =>
  CHAPTERS[chapter].filter((step) => !step.skip?.(ctx));

export interface ResolvedStep {
  step: TourStep;
  index: number;
  total: number;
}

/**
 * The step to show on `path`, or null when the page belongs to none of them yet (the person took a
 * detour; the tour waits for them to come back). When the current step's page is behind them —
 * the install landed on the project rather than its checklist — the tour moves on to the step right
 * after it. Never further: a person who wanders to the board mid-tour must not skip the run.
 */
export function resolveStep(chapter: TourChapter, stepId: string, path: string, ctx: TourContext): ResolvedStep | null {
  const steps = stepsFor(chapter, ctx);
  const current = Math.max(
    0,
    steps.findIndex((step) => step.id === stepId),
  );
  const index = [current, current + 1].find((i) => steps[i]?.page.test(path));
  if (index === undefined) return null;
  return { step: steps[index], index, total: steps.length };
}

export function nextStepId(chapter: TourChapter, stepId: string, ctx: TourContext): string | null {
  const steps = stepsFor(chapter, ctx);
  const index = steps.findIndex((step) => step.id === stepId);
  return steps[index + 1]?.id ?? null;
}

export const projectIdFrom = (path: string) => path.match(/^\/company\/projects\/(\d+)/)?.[1] ?? null;
