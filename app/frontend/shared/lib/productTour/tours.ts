import {
  companyProjectBoardPath,
  companyProjectOverviewIndexPath,
  companyProjectSessionsPath,
  companyProjectWorkflowRunPath,
  companyProjectWorkflowsPath,
} from 'shared/routes';

import { tourSelector } from './waitForTarget';

export type TourVariant = 'a' | 'b';

/** What a step may read: ids the tour picked up on earlier pages, and facts about the member. */
export interface TourContext {
  projectId: number | null;
  runId: number | null;
  /** The run's state as the status endpoint last reported it; null before it was asked. */
  runState: string | null;
  runFinished: boolean;
  hasAgent: boolean;
  firstProjectId: number | null;
}

export interface TourStep {
  id: string;
  /** The Inertia component the step is shown on, or `any`. */
  page: string;
  /** A `data-tour` key. Without one (and without `targetSelector`) the step is a centred popover. */
  target?: string;
  /** A CSS selector for the target, for one a single `data-tour` key cannot name (a card in a column). */
  targetSelector?: string;
  /** How long to wait for the target, when it only shows up after the server has done something. */
  targetWaitMs?: number;
  /** For `click` steps: the `data-tour` key a click must land in, when it is not the target itself. */
  clickTarget?: string;
  /**
   * `click`: the member clicks the highlighted element and the tour follows the page that opens.
   * `appear`: the member works inside the highlighted element until `appears` matches something.
   * `next`: a Next button. `finish`: the last step.
   */
  advance: 'click' | 'appear' | 'next' | 'finish';
  /** For `appear` steps: the CSS selector whose first match moves the tour on. */
  appears?: string;
  title: string;
  body: string | ((ctx: TourContext) => string);
  /** The step after this one; the following step in the list when absent. */
  next?: (ctx: TourContext) => string;
  /** A page to visit when the member presses Next. */
  visitOnNext?: (ctx: TourContext) => string | null;
  /** Open the sidebar and its groups first, so a sidebar target is on screen. */
  expandSidebar?: boolean;
  /** Ask the server for the run's state before showing the step. */
  needsRunStatus?: boolean;
  /** Click the target before highlighting it (a tab that has to be opened). */
  openTarget?: (ctx: TourContext) => boolean;
  /** Before a run is started: without a connected agent the step points to the agent setup instead. */
  needsAgent?: boolean;
}

export const HELLO_FLOW_CARD = 'template-card:aixle/hello-flow';

/** The step the "first run finished" toast brings the member back to. */
export const RUN_RESULT_STEP = 'a17';

const CARD = tourSelector('board-card');
const CARD_IN_TRIGGER_COLUMN = `${tourSelector('board-trigger-column')} ${CARD}`;
// The trigger has a short cooldown and the run is created by the server, so the card's run shows up
// a few seconds after the drop.
const RUN_APPEARS_MS = 60_000;

const TOUR_A: TourStep[] = [
  {
    id: 'a1',
    page: 'Projects/IndexPage',
    target: 'nav-templates',
    advance: 'click',
    expandSidebar: true,
    title: 'Templates',
    body: 'Templates are ready-made setups: agents, workflows and a board, already wired together. The easiest way to start.',
  },
  {
    id: 'a2',
    page: 'Templates/IndexPage',
    target: HELLO_FLOW_CARD,
    advance: 'click',
    title: 'Hello Flow',
    body: 'Most templates connect to your tools, like GitHub or Slack. Hello Flow needs nothing, so it’s perfect for a first try.',
  },
  {
    id: 'a3',
    page: 'Templates/ShowPage',
    target: 'template-parts',
    advance: 'next',
    title: 'What a project is made of',
    body:
      'Every Flow project has four parts: a Board with tasks, Agents that do the work, Workflows that tell agents ' +
      'what to do, and Triggers that start workflows on their own.',
  },
  {
    id: 'a4',
    page: 'Templates/ShowPage',
    target: 'template-install',
    advance: 'click',
    title: 'Install it',
    body: 'Install it.',
  },
  {
    id: 'a5',
    page: 'Templates/InstallPage',
    target: 'install-form',
    clickTarget: 'install-submit',
    advance: 'click',
    title: 'A new project',
    body:
      'Templates install into a project: a separate workspace with its own board, agents and settings. ' +
      'This one gets a new project. Click Install.',
  },
  {
    id: 'a6',
    page: 'Projects/TemplateInstalls/ShowPage',
    target: 'setup-trigger-activate',
    advance: 'click',
    title: 'Switch the trigger on',
    body:
      'This checklist shows what a template still needs: secrets, integrations, and triggers to switch on. ' +
      'Triggers start inactive, so nothing runs without you. Hello Flow’s trigger starts the workflow when a card ' +
      'enters Researching. Activate it.',
  },
  {
    id: 'a7',
    page: 'Projects/TemplateInstalls/ShowPage',
    target: 'setup-checklist',
    advance: 'next',
    title: 'Ready to go',
    body: 'The trigger is on, and Hello Flow needs nothing else. Let’s look at the project.',
    visitOnNext: (ctx) => (ctx.projectId ? companyProjectOverviewIndexPath(ctx.projectId) : null),
  },
  {
    id: 'a8',
    page: 'Projects/Overview/OverviewPage',
    target: 'sidebar-nav',
    advance: 'next',
    expandSidebar: true,
    title: 'Work and Resources',
    body:
      'Work is where things happen: tasks, workflows, triggers, runs and results. ' +
      'Resources is what agents use: agents, skills, connectors, repositories.',
    visitOnNext: (ctx) => (ctx.projectId ? companyProjectWorkflowsPath(ctx.projectId) : null),
  },
  {
    id: 'a9',
    page: 'Projects/Workflows/WorkflowsPage',
    target: 'workflow-card',
    advance: 'next',
    title: 'Workflows',
    body:
      'A workflow is a chain of steps. Each step is an instruction that an agent carries out. ' +
      'Hello Flow has two: research a company, then lay out a one-page profile.',
    visitOnNext: (ctx) => (ctx.projectId ? companyProjectBoardPath(ctx.projectId) : null),
  },
  {
    id: 'a10',
    page: 'Projects/Board/BoardPage',
    target: 'board-add-task',
    advance: 'click',
    needsAgent: true,
    title: 'Add a task',
    body: 'Work starts on the board. Add a card to To research.',
  },
  {
    id: 'a11',
    page: 'Projects/Board/BoardPage',
    target: 'create-task-form',
    advance: 'appear',
    appears: CARD,
    title: 'Name it after a company',
    body: 'Type a company name as the title, for example Stripe or stripe.com, and click Create task.',
  },
  {
    id: 'a12',
    page: 'Projects/Board/BoardPage',
    target: 'board',
    advance: 'appear',
    appears: CARD_IN_TRIGGER_COLUMN,
    needsAgent: true,
    title: 'Drag it to Researching',
    body:
      'Researching has a trigger: a card that enters it starts Hello Flow. Drag your card there. ' +
      'In real work this is how workflows start, without pressing Run.',
  },
  {
    id: 'a13',
    page: 'Projects/Board/BoardPage',
    targetSelector: CARD_IN_TRIGGER_COLUMN,
    clickTarget: 'board-card',
    advance: 'click',
    title: 'A run started',
    body: 'The trigger started Hello Flow for this card. Open the card to follow it.',
  },
  {
    id: 'a14',
    page: 'Projects/Board/BoardPage',
    target: 'task-latest-run',
    targetWaitMs: RUN_APPEARS_MS,
    advance: 'next',
    title: 'The card’s run',
    body: 'Every run a card starts is listed on it. Let’s watch this one.',
    visitOnNext: (ctx) => (ctx.projectId && ctx.runId ? companyProjectWorkflowRunPath(ctx.projectId, ctx.runId) : null),
  },
  {
    id: 'a15',
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-sessions',
    advance: 'next',
    title: 'A run',
    body: 'This is a run. Each step runs as a session: an agent working in its own container.',
  },
  {
    id: 'a16',
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-console',
    advance: 'next',
    title: 'Watch it live',
    body: 'Watch the agent work live. If a run fails, this is where you find out why.',
  },
  {
    id: RUN_RESULT_STEP,
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-assets-tab',
    advance: 'next',
    needsRunStatus: true,
    openTarget: (ctx) => ctx.runState === 'completed',
    title: 'Results',
    body: (ctx) => {
      if (!ctx.runFinished) {
        return 'It takes about 3 minutes. We’ll let you know when it’s done; the one-pager will be on the card and here, in Assets.';
      }
      if (ctx.runState !== 'completed') {
        return 'This run did not finish. The card’s comment says why: if its title is not a company name, rename it and drag it to Researching again.';
      }
      return 'Here is the result: a one-page profile of the company. It is also attached to the card, which moved to Done.';
    },
  },
  {
    id: 'a18',
    page: 'any',
    advance: 'finish',
    title: 'That’s Flow',
    body:
      'A board with tasks, triggers that start workflows, agents that run them, and results on the card and in ' +
      'Assets. Next: install another template or describe your own process in AI Builder.',
  },
];

const TOUR_B: TourStep[] = [
  {
    id: 'b1',
    page: 'Projects/IndexPage',
    target: 'projects-list',
    advance: 'next',
    title: 'Projects',
    body: 'Each project is a separate workspace with its own board, workflows and agents.',
    next: (ctx) => (ctx.firstProjectId ? 'b2' : 'b4'),
    visitOnNext: (ctx) => (ctx.firstProjectId ? companyProjectBoardPath(ctx.firstProjectId) : null),
  },
  {
    id: 'b2',
    page: 'Projects/Board/BoardPage',
    target: 'board',
    advance: 'next',
    title: 'Tasks',
    body: 'The board holds the project’s tasks. Moving a card into a column can start a workflow.',
    visitOnNext: (ctx) => (ctx.firstProjectId ? companyProjectSessionsPath(ctx.firstProjectId) : null),
  },
  {
    id: 'b3',
    page: 'Projects/Sessions/SessionsRunsPage',
    target: 'sessions-list',
    advance: 'next',
    title: 'Sessions & Runs',
    body: 'Every agent session and workflow run of the project is listed here, live.',
  },
  {
    id: 'b4',
    page: 'any',
    advance: 'finish',
    title: 'That’s Flow',
    body: 'You can follow everything here. Ask an admin to give you edit access to run workflows.',
  },
];

export const TOURS: Record<TourVariant, TourStep[]> = { a: TOUR_A, b: TOUR_B };

export function firstStepId(variant: TourVariant): string {
  return TOURS[variant][0].id;
}

export function findStep(variant: TourVariant, stepId: string): TourStep | undefined {
  return TOURS[variant].find((step) => step.id === stepId);
}

/** The step after `step`, or null at the end of the tour. */
export function nextStepId(variant: TourVariant, step: TourStep, ctx: TourContext): string | null {
  if (step.next) return step.next(ctx);
  const steps = TOURS[variant];
  const index = steps.indexOf(step);
  return steps[index + 1]?.id ?? null;
}

export function stepBody(step: TourStep, ctx: TourContext): string {
  return typeof step.body === 'function' ? step.body(ctx) : step.body;
}
