import {
  companyProjectBoardPath,
  companyProjectOverviewIndexPath,
  companyProjectSessionsPath,
  companyProjectWorkflowsPath,
} from 'shared/routes';

export type TourVariant = 'a' | 'b';

/** What a step may read: ids the tour picked up on earlier pages, and facts about the member. */
export interface TourContext {
  projectId: number | null;
  runId: number | null;
  /** The run's state as the status endpoint last reported it; null before it was asked. */
  runState: string | null;
  runFinished: boolean;
  /** True when the member came back to the run from the "first run finished" toast. */
  resumedFromToast: boolean;
  hasAgent: boolean;
  firstProjectId: number | null;
}

export interface TourStep {
  id: string;
  /** The Inertia component the step is shown on, or `any`. */
  page: string;
  /** A `data-tour` key. Without one the step is a centred popover. */
  target?: string;
  /** For `click` steps: the `data-tour` key a click must land in, when it is not the target itself. */
  clickTarget?: string;
  /**
   * `click`: the member clicks the highlighted element and the tour follows the page that opens.
   * `next`: a Next button. `finish`: the last step.
   */
  advance: 'click' | 'next' | 'finish';
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

// A run still going sends the member to the board meanwhile; a failed run, or the
// second look at a finished one from the toast, goes straight to the end.
const showsBoardAfterRun = (ctx: TourContext) =>
  !ctx.runFinished || (ctx.runState === 'completed' && !ctx.resumedFromToast);

const RUN_PENDING_COPY = 'It takes ~1–2 min. Meanwhile, let’s look at the board.';

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
    target: 'setup-checklist',
    advance: 'next',
    title: 'Set up checklist',
    body:
      'This checklist shows what a template still needs: secrets, integrations, and triggers to switch on. ' +
      'Triggers start inactive, so nothing runs without you. Hello Flow only has a trigger you can switch on later.',
    visitOnNext: (ctx) => (ctx.projectId ? companyProjectOverviewIndexPath(ctx.projectId) : null),
  },
  {
    id: 'a7',
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
    id: 'a8',
    page: 'Projects/Workflows/WorkflowsPage',
    target: 'workflow-card',
    advance: 'next',
    title: 'Workflows',
    body: 'A workflow is a chain of steps. Each step is an instruction that an agent carries out.',
  },
  {
    id: 'a9',
    page: 'Projects/Workflows/WorkflowsPage',
    target: 'workflow-run',
    advance: 'click',
    needsAgent: true,
    title: 'Run it',
    body: 'You can start a workflow manually, like now, or let a trigger start it for you. Run it.',
  },
  {
    id: 'a10',
    page: 'Projects/Workflows/WorkflowsPage',
    target: 'run-drawer-submit',
    advance: 'click',
    needsAgent: true,
    title: 'Run options',
    body: 'Here you can pick the model, the runner and repositories for this run. The defaults are fine.',
  },
  {
    id: 'a11',
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-sessions',
    advance: 'next',
    title: 'A run',
    body: 'This is a run. Each step runs as a session: an agent working in its own container.',
  },
  {
    id: 'a12',
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-console',
    advance: 'next',
    title: 'Watch it live',
    body: 'Watch the agent work live. If a run fails, this is where you find out why.',
  },
  {
    id: 'a13',
    page: 'Projects/WorkflowRuns/ShowPage',
    target: 'run-assets-tab',
    advance: 'next',
    needsRunStatus: true,
    openTarget: (ctx) => ctx.runState === 'completed',
    title: 'Results',
    body: (ctx) => {
      if (!ctx.runFinished) return RUN_PENDING_COPY;
      if (ctx.runState !== 'completed') return 'This run failed. Open Sessions & Runs to see why.';
      return 'When the run finishes, its results appear here as assets.';
    },
    next: (ctx) => (showsBoardAfterRun(ctx) ? 'a14' : 'a15'),
    visitOnNext: (ctx) => (ctx.projectId && showsBoardAfterRun(ctx) ? companyProjectBoardPath(ctx.projectId) : null),
  },
  {
    id: 'a14',
    page: 'Projects/Board/BoardPage',
    target: 'board-trigger-column',
    advance: 'next',
    title: 'Triggers on the board',
    body:
      'In real work you rarely press Run. Move a card into this column, and its trigger starts the workflow. ' +
      'Switch the trigger on in Triggers to try it.',
  },
  {
    id: 'a15',
    page: 'any',
    advance: 'finish',
    title: 'That’s Flow',
    body:
      'A board with tasks, workflows run by agents, triggers that start them, and results in assets. ' +
      'Next: install another template or describe your own process in AI Builder.',
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
