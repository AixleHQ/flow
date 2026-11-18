import { router, usePage } from '@inertiajs/react';
import { Button, Group, Modal, Stack, Text } from '@mantine/core';
import { type Driver, driver } from 'driver.js';
import 'driver.js/dist/driver.css';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import type { SharedProps } from 'shared/ui/types';

import './productTour.css';
import { nextStepId, projectIdFrom, resolveStep, stepsFor } from './resolveStep';
import type { TourChapter, TourContext, TourStep } from './steps';
import { tourSelector } from './targets';
import {
  markOfferedThisVisit,
  offeredThisVisit,
  onTourStartRequest,
  readOffer,
  readTourState,
  shouldOffer,
  type TourState,
  updateOffer,
  writeTourState,
} from './tourStore';

const TARGET_WAIT_MS = 6000;
// A target that is often absent (the live console of a run that already ended) is not worth a long wait.
const OPTIONAL_TARGET_WAIT_MS = 1500;
const SETTLE_MS = 300;
const PROJECTS_PATH = /^\/company\/projects\/?$/;

function waitForElement(selector: string, timeoutMs: number, signal: AbortSignal): Promise<Element | null> {
  return new Promise((resolve) => {
    const started = performance.now();
    const poll = () => {
      if (signal.aborted) return resolve(null);
      const el = document.querySelector(selector);
      if (el && el.getClientRects().length > 0) return resolve(el);
      if (performance.now() - started > timeoutMs) return resolve(null);
      window.setTimeout(poll, 100);
    };
    poll();
  });
}

/**
 * The product tour (Flow Dev #51): a first-visit offer on Projects, then one highlighted element
 * at a time across the pages the steps belong to. Mounted once in AuthLayout.
 */
export function ProductTour() {
  const enabled = useFeatureFlag('productTour');
  const { currentUser, permissions } = usePage<SharedProps>().props;
  const { url } = usePage();
  const path = url.split('?')[0];

  const [tour, setTour] = useState<TourState | null>(() => readTourState());
  const [offerOpen, setOfferOpen] = useState(false);
  // The page a Next button is taking the person to. Until it opens, the page still on screen must not
  // be read as the next step's: A15 belongs to every project page, the run page included.
  const [visiting, setVisiting] = useState<string | null>(null);

  const chapter: TourChapter = permissions?.canWrite === false ? 'viewer' : 'first-run';
  const ctx: TourContext = useMemo(
    () => ({ projectId: projectIdFrom(path), hasAgent: (currentUser?.agentCredentials?.length ?? 0) > 0 }),
    [path, currentUser],
  );

  const save = useCallback((next: TourState | null) => {
    writeTourState(next);
    setTour(next);
  }, []);

  const start = useCallback(() => {
    setOfferOpen(false);
    const first = stepsFor(chapter, ctx)[0];
    save({ chapter, stepId: first.id });
    if (!first.page.test(window.location.pathname)) router.visit('/company/projects');
  }, [chapter, ctx, save]);

  const finish = useCallback(
    (completed: boolean) => {
      save(null);
      if (currentUser) updateOffer(currentUser.id, completed ? { completed: true } : { dismissed: true });
    },
    [currentUser, save],
  );

  useEffect(() => (enabled ? onTourStartRequest(start) : undefined), [enabled, start]);

  // `?tour=first-run` / `?tour=viewer` starts a chapter directly, for QA.
  useEffect(() => {
    if (!enabled) return;
    const requested = new URLSearchParams(url.split('?')[1] ?? '').get('tour');
    if (requested === 'first-run' || requested === 'viewer') {
      const first = stepsFor(requested, ctx)[0];
      save({ chapter: requested, stepId: first.id });
    }
    // Only a new URL can carry a new request.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, url]);

  // Scenario A0: the offer, shown on Projects to someone who has finished onboarding.
  useEffect(() => {
    if (!enabled || !currentUser || tour || !PROJECTS_PATH.test(path)) return;
    if (currentUser.onboardingState !== 'completed' || offeredThisVisit()) return;
    if (!shouldOffer(readOffer(currentUser.id))) return;
    markOfferedThisVisit();
    setOfferOpen(true);
  }, [enabled, currentUser, tour, path]);

  useEffect(() => {
    if (!enabled || !tour) return;
    if (visiting) {
      if (visiting !== path) return;
      setVisiting(null);
      return;
    }
    const resolved = resolveStep(tour.chapter, tour.stepId, path, ctx);
    if (!resolved) return;
    if (resolved.step.id !== tour.stepId) {
      save({ ...tour, stepId: resolved.step.id });
      return;
    }

    const aborter = new AbortController();
    let instance: Driver | null = null;
    let moving = false;

    const advance = (step: TourStep, byClick: boolean) => {
      moving = true;
      instance?.destroy();
      const next = nextStepId(tour.chapter, step.id, ctx);
      if (!next) return finish(true);
      save({ ...tour, stepId: next });
      // A clicked link or button navigates by itself.
      const destination = byClick ? null : step.goTo?.(ctx);
      if (destination) {
        setVisiting(destination);
        // onFinish runs before the new page renders; only a visit that ended somewhere else (a redirect,
        // an error) gives up waiting here — a successful one is released by the path check above.
        router.visit(destination, {
          onFinish: () => {
            if (window.location.pathname !== destination) setVisiting(null);
          },
        });
      }
    };

    const show = async () => {
      const { step, index, total } = resolved;
      const element = step.target
        ? await waitForElement(
            tourSelector(step.target),
            step.optionalTarget ? OPTIONAL_TARGET_WAIT_MS : TARGET_WAIT_MS,
            aborter.signal,
          )
        : null;
      // Drawers and modals slide in: measure the target once it has settled, or the cut-out lands beside it.
      if (element) await new Promise((resolve) => window.setTimeout(resolve, SETTLE_MS));
      if (aborter.signal.aborted) return;
      // A click step whose target never appeared would leave the person stuck: let them move on.
      const byClick = step.advance === 'click' && element !== null;
      const isLast = index === total - 1;

      instance = driver({
        allowClose: true,
        overlayClickBehavior: 'none',
        stagePadding: 6,
        stageRadius: 8,
        popoverClass: 'aixle-tour-popover',
        overlayOpacity: 0.72,
        onDestroyStarted: () => {
          if (moving) return;
          moving = true;
          instance?.destroy();
          finish(false);
        },
      });

      if (byClick && element) {
        element.addEventListener(
          'click',
          (event) => {
            const clicked = event.target instanceof Element ? event.target : null;
            const actionable = clicked?.closest('a, button');
            // A whole card is highlighted but only its link navigates: follow the link wherever the card was clicked.
            const link = actionable ? null : element.querySelector<HTMLElement>('a, button');
            advance(step, true);
            link?.click();
          },
          // Aborted with the step: a click on Run after the tour was closed must not bring it back.
          { once: true, capture: true, signal: aborter.signal },
        );
      }

      instance.highlight({
        element: element ?? undefined,
        popover: {
          title: step.title,
          description: step.body,
          side: element ? step.side : undefined,
          showProgress: true,
          progressText: `${index + 1} of ${total}`,
          showButtons: byClick ? ['close'] : ['next', 'close'],
          nextBtnText: isLast ? 'Finish' : 'Next',
          onNextClick: () => advance(step, false),
        },
      });
    };

    show();
    return () => {
      aborter.abort();
      moving = true;
      instance?.destroy();
    };
  }, [enabled, tour, visiting, path, ctx, save, finish]);

  if (!enabled || !currentUser) return null;

  const notNow = () => {
    updateOffer(currentUser.id, { notNowCount: readOffer(currentUser.id).notNowCount + 1 });
    setOfferOpen(false);
  };
  const neverAgain = () => {
    updateOffer(currentUser.id, { dismissed: true });
    setOfferOpen(false);
  };

  return (
    <Modal opened={offerOpen} onClose={neverAgain} title="Want a quick tour?" centered size="md">
      <Stack gap="lg">
        <Text size="sm" c="var(--app-text-secondary)">
          We&apos;ll show you how Flow works and run your first workflow together. Takes about 5 minutes.
        </Text>
        <Group justify="space-between">
          <Button variant="subtle" color="gray" onClick={neverAgain}>
            Don&apos;t show again
          </Button>
          <Group gap="xs">
            <Button variant="default" onClick={notNow}>
              Not now
            </Button>
            <Button onClick={start}>Yes, show me</Button>
          </Group>
        </Group>
      </Stack>
    </Modal>
  );
}
