import { router } from '@inertiajs/react';
import { Anchor } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import {
  companyProductTourPath,
  companyProjectWorkflowRunPath,
  companyProjectsPath,
  profilePath,
  statusCompanyProjectWorkflowRunPath,
} from 'shared/routes';

import { createDriverHighlighter, type Highlight, type TourHighlighter } from './highlighter';
import { EXPAND_SIDEBAR_EVENT } from './sidebarEvent';
import {
  findStep,
  firstStepId,
  nextStepId,
  stepBody,
  type TourContext,
  type TourStep,
  type TourVariant,
} from './tours';
import { readStoredTour, type StoredTour, type WatchedRun, writeStoredTour } from './tourStorage';
import { tourSelector, waitForTarget } from './waitForTarget';

/** The part of an Inertia page the tour reads. */
export interface TourPage {
  component: string;
  props: Record<string, unknown>;
}

export interface ProductTourApi {
  active: boolean;
  start: (variant: TourVariant) => void;
  skip: () => void;
}

interface RunStatus {
  state: string;
  finished: boolean;
}

const RUN_PAGE = 'Projects/WorkflowRuns/ShowPage';
// The pages the tour takes its project and run from: the install it just made, the run it just started.
const CAPTURE_PAGES = ['Projects/TemplateInstalls/ShowPage', RUN_PAGE];
const RUN_WATCH_LIMIT_MS = 15 * 60 * 1000;

const ProductTourContext = createContext<ProductTourApi | null>(null);

const idOf = (value: unknown): number | null => {
  const id = (value as { id?: unknown } | null | undefined)?.id;
  return typeof id === 'number' ? id : null;
};

const hasAgent = (page: TourPage | null) =>
  ((page?.props.currentUser as { configuredAgents?: unknown[] } | null | undefined)?.configuredAgents?.length ?? 0) > 0;

const firstProjectId = (page: TourPage | null) => {
  const projects = page?.props.projects;
  return Array.isArray(projects) ? idOf(projects[0]) : null;
};

const tourEnabled = (page: TourPage | null) =>
  Boolean((page?.props.features as { productTour?: boolean } | undefined)?.productTour);

// Takes the pending step once its page is there, and the ids the tour needs from the page. The same
// object when nothing changed: live pages reload their props, and each reload is a navigate event.
function arriveAt(tour: StoredTour, page: TourPage, pendingStepId: string | null | undefined): StoredTour {
  const moved =
    pendingStepId && findStep(tour.variant, pendingStepId)?.page === page.component
      ? { ...tour, stepId: pendingStepId }
      : tour;
  return withCapturedIds(moved, page);
}

function withCapturedIds(tour: StoredTour, page: TourPage): StoredTour {
  if (!CAPTURE_PAGES.includes(page.component)) return tour;

  const projectId = idOf(page.props.project) ?? tour.projectId;
  const runId = page.component === RUN_PAGE ? (idOf(page.props.run) ?? tour.runId) : tour.runId;
  return projectId === tour.projectId && runId === tour.runId ? tour : { ...tour, projectId, runId };
}

async function fetchRunStatus(projectId: number, runId: number): Promise<RunStatus | null> {
  try {
    const response = await apiFetch(statusCompanyProjectWorkflowRunPath(projectId, runId));
    return response.ok ? ((await response.json()) as RunStatus) : null;
  } catch {
    return null;
  }
}

function recordFinished(variant: TourVariant): void {
  // A failed write only means Getting started shows up once more after the next sign-in.
  apiFetch(companyProductTourPath(), {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ variant }),
  }).catch(() => {});
}

interface ProductTourProviderProps {
  /** The page the app booted with: Inertia announces only the visits after it. */
  initialPage: TourPage | null;
  highlighter?: TourHighlighter;
  targetTimeoutMs?: number;
  pollIntervalMs?: number;
  children: ReactNode;
}

/**
 * Runs the product tour (docs/design/product-tour.md). Mounted once around the Inertia app, the only
 * tree that outlives page visits: it follows the pages, waits for each step's `data-tour` target and
 * has the highlighter draw one step at a time.
 */
export function ProductTourProvider({
  initialPage,
  highlighter: injectedHighlighter,
  targetTimeoutMs = 5000,
  pollIntervalMs = 10_000,
  children,
}: ProductTourProviderProps) {
  const [page, setPage] = useState<TourPage | null>(initialPage);
  const [tour, setTour] = useState<StoredTour | null>(() => {
    const stored = readStoredTour().tour;
    if (!stored) return null;
    const { pendingStepId, ...resumed } = stored;
    return initialPage ? arriveAt(resumed, initialPage, pendingStepId) : resumed;
  });
  const [watched, setWatched] = useState<WatchedRun | null>(() => readStoredTour().watched);
  const pendingStepRef = useRef<string | null>(null);
  const highlighterRef = useRef<TourHighlighter | null>(injectedHighlighter ?? null);

  const highlighter = useCallback(() => {
    highlighterRef.current ??= createDriverHighlighter();
    return highlighterRef.current;
  }, []);

  useEffect(() => writeStoredTour({ tour, watched }), [tour, watched]);

  useEffect(
    () =>
      router.on('navigate', (event) => {
        const next: TourPage = { component: event.detail.page.component, props: event.detail.page.props };
        const pendingStepId = pendingStepRef.current;
        pendingStepRef.current = null;
        setTour((current) => (current ? arriveAt(current, next, pendingStepId) : current));
        setPage(next);
      }),
    [],
  );

  useEffect(() => () => highlighterRef.current?.clear(), []);

  const finish = useCallback(
    (variant: TourVariant) => {
      highlighter().clear();
      setTour(null);
      recordFinished(variant);
    },
    [highlighter],
  );

  const start = useCallback(
    (variant: TourVariant) => {
      highlighter().clear();
      setTour({ variant, stepId: firstStepId(variant), projectId: null, runId: null, resumedFromToast: false });
      router.visit(companyProjectsPath());
    },
    [highlighter],
  );

  const skip = useCallback(() => {
    if (tour) finish(tour.variant);
  }, [finish, tour]);

  const advance = useCallback(
    (step: TourStep, current: StoredTour, ctx: TourContext) => {
      const nextId = nextStepId(current.variant, step, ctx);
      if (!nextId) {
        finish(current.variant);
        return;
      }
      if (step.needsRunStatus && !ctx.runFinished && current.projectId && current.runId) {
        setWatched({ projectId: current.projectId, runId: current.runId, since: Date.now() });
      }
      const url = step.visitOnNext?.(ctx) ?? null;
      highlighter().clear();
      setTour({ ...current, stepId: nextId });
      if (url) router.visit(url);
    },
    [finish, highlighter],
  );

  const enabled = tourEnabled(page);
  const memberHasAgent = hasAgent(page);
  const memberFirstProjectId = firstProjectId(page);
  const component = page?.component ?? null;

  useEffect(() => {
    if (!tour || !component) return;
    if (!enabled) {
      highlighter().clear();
      return;
    }
    const step = findStep(tour.variant, tour.stepId);
    if (!step) {
      setTour(null);
      return;
    }
    highlighter().clear();
    if (step.page !== 'any' && step.page !== component) return;

    let cancelled = false;
    let removeClickListener: (() => void) | null = null;
    const skipAction = { label: 'Skip tour', onClick: () => finish(tour.variant) };
    const show = (highlight: Omit<Highlight, 'actions'>, actions = [skipAction]) =>
      highlighter().show({ ...highlight, actions });

    const present = async () => {
      let ctx: TourContext = {
        projectId: tour.projectId,
        runId: tour.runId,
        runState: null,
        runFinished: false,
        resumedFromToast: tour.resumedFromToast,
        hasAgent: memberHasAgent,
        firstProjectId: memberFirstProjectId,
      };
      if (step.needsRunStatus && tour.projectId && tour.runId) {
        const status = await fetchRunStatus(tour.projectId, tour.runId);
        if (cancelled) return;
        ctx = { ...ctx, runState: status?.state ?? null, runFinished: status?.finished ?? false };
      }

      if (step.needsAgent && !ctx.hasAgent) {
        show({
          element: document.querySelector(tourSelector('agent-nudge')) ?? undefined,
          title: 'Connect an agent to run',
          description:
            'Flow runs workflows with your AI agent. Connect one in your profile, then come back here and run the workflow.',
          interactive: false,
          primary: {
            label: 'Open profile',
            onClick: () => {
              highlighter().clear();
              router.visit(profilePath());
            },
          },
        });
        return;
      }

      if (step.expandSidebar) window.dispatchEvent(new CustomEvent(EXPAND_SIDEBAR_EVENT));
      const element = step.target ? await waitForTarget(step.target, targetTimeoutMs) : null;
      if (cancelled) return;

      if (step.target && !element) {
        const nextId = nextStepId(tour.variant, step, ctx);
        const nextPage = nextId ? findStep(tour.variant, nextId)?.page : null;
        // Skipping only helps when the next step can be reached from here without the click.
        const canSkip = step.advance !== 'click' || nextPage === 'any' || nextPage === component;
        show(
          { title: step.title, description: stepBody(step, ctx), interactive: false },
          [
            { label: 'End tour', onClick: () => finish(tour.variant) },
            ...(canSkip ? [{ label: 'Skip this step', onClick: () => advance(step, tour, ctx) }] : []),
          ],
        );
        return;
      }

      if (element instanceof HTMLElement && step.openTarget?.(ctx)) element.click();

      const base = { element: element ?? undefined, title: step.title, description: stepBody(step, ctx) };
      if (step.advance !== 'click') {
        const last = step.advance === 'finish';
        show({
          ...base,
          interactive: false,
          primary: {
            label: last ? 'Finish' : 'Next',
            onClick: () => (last ? finish(tour.variant) : advance(step, tour, ctx)),
          },
        });
        return;
      }

      show({ ...base, interactive: true });
      const clickKey = step.clickTarget ?? step.target ?? '';
      const onClick = (event: MouseEvent) => {
        if (!(event.target instanceof Element) || !event.target.closest(tourSelector(clickKey))) return;
        const nextId = nextStepId(tour.variant, step, ctx);
        if (!nextId) return;
        if (findStep(tour.variant, nextId)?.page === component) {
          // After the click has done its work (a drawer opening), not before.
          window.setTimeout(() => {
            highlighter().clear();
            setTour((current) => (current ? { ...current, stepId: nextId } : current));
          }, 0);
        } else {
          // Not state: the step stays on screen until the page changes. Written through for a click
          // that loads a whole new page, which this provider only sees again as its boot page.
          pendingStepRef.current = nextId;
          writeStoredTour({ tour: { ...tour, pendingStepId: nextId }, watched: readStoredTour().watched });
        }
      };
      document.addEventListener('click', onClick, true);
      removeClickListener = () => document.removeEventListener('click', onClick, true);
    };

    void present();
    return () => {
      cancelled = true;
      removeClickListener?.();
    };
  }, [
    tour,
    component,
    enabled,
    memberHasAgent,
    memberFirstProjectId,
    targetTimeoutMs,
    highlighter,
    finish,
    advance,
  ]);

  const openRunResult = useCallback((run: WatchedRun) => {
    notifications.hide(`product-tour-run-${run.runId}`);
    setTour({ variant: 'a', stepId: 'a13', projectId: run.projectId, runId: run.runId, resumedFromToast: true });
    router.visit(companyProjectWorkflowRunPath(run.projectId, run.runId));
  }, []);

  useEffect(() => {
    if (!watched) return;

    const timer = window.setInterval(async () => {
      if (Date.now() - watched.since > RUN_WATCH_LIMIT_MS) {
        setWatched(null);
        return;
      }
      const status = await fetchRunStatus(watched.projectId, watched.runId);
      if (!status?.finished) return;

      setWatched(null);
      notifications.show({
        id: `product-tour-run-${watched.runId}`,
        title: 'Your first run finished',
        autoClose: false,
        message: (
          <Anchor component="button" type="button" size="sm" onClick={() => openRunResult(watched)}>
            See the result
          </Anchor>
        ),
      });
    }, pollIntervalMs);
    return () => window.clearInterval(timer);
  }, [watched, pollIntervalMs, openRunResult]);

  const api = useMemo<ProductTourApi>(() => ({ active: tour !== null, start, skip }), [tour, start, skip]);

  return <ProductTourContext.Provider value={api}>{children}</ProductTourContext.Provider>;
}

const INACTIVE: ProductTourApi = { active: false, start: () => {}, skip: () => {} };

/** The running tour, if any. Outside ProductTourProvider (a component test) nothing starts. */
export function useProductTour(): ProductTourApi {
  return useContext(ProductTourContext) ?? INACTIVE;
}
