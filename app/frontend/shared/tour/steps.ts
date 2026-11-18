import type { TourTarget } from './targets';

export type TourChapter = 'first-run' | 'viewer';

/** What a step knows about the person and the page it is shown on. */
export interface TourContext {
  projectId: string | null;
  hasAgent: boolean;
}

export interface TourStep {
  id: string;
  /** The page the step belongs to, matched against `location.pathname`. */
  page: RegExp;
  /** No target: the popover is shown in the middle of the screen. */
  target?: TourTarget;
  title: string;
  body: string;
  /**
   * `click`: the step moves on when the person clicks the highlighted element (the page under the
   * mask is not clickable). `next`: the popover's own button moves it on.
   */
  advance: 'click' | 'next';
  /**
   * The page to open for the step after this one, when the popover's button moved the tour on. A
   * click step's own link already goes there; its `goTo` serves the fallback when the target is
   * missing (a collapsed sidebar group).
   */
  goTo?: (ctx: TourContext) => string | null;
  /** The step is left out for this person. */
  skip?: (ctx: TourContext) => boolean;
  /** Shown without a highlight when the target does not appear in time (a run with no live console). */
  optionalTarget?: boolean;
  side?: 'top' | 'right' | 'bottom' | 'left';
}

const PROJECTS = /^\/company\/projects\/?$/;
const IN_PROJECT = /^\/company\/projects\/\d+(\/|$)/;
const project = (ctx: TourContext, path: string) =>
  ctx.projectId ? `/company/projects/${ctx.projectId}${path}` : null;

export const HELLO_FLOW_TEMPLATE = 'aixle/hello-flow';

// Copy follows the scenario in Flow Dev #51 (product-tour-scenario.md, section 3). Step ids keep
// the scenario's numbering so a copy change can be traced back to the row it came from.
const FIRST_RUN: TourStep[] = [
  {
    id: 'A1',
    // Only the company sidebar has Templates; a project's does not.
    page: PROJECTS,
    target: 'sidebar-templates',
    title: 'Start from a template',
    body: 'Templates are ready-made setups: agents, workflows and a board, already wired together. The easiest way to start.',
    advance: 'click',
    side: 'right',
    goTo: () => '/templates',
  },
  {
    id: 'A2',
    page: /^\/templates\/?$/,
    target: 'template-card',
    title: 'Pick Hello Flow',
    body: "Most templates connect to your tools, like GitHub or Slack. Hello Flow needs nothing, so it's perfect for a first try.",
    advance: 'click',
  },
  {
    id: 'A3',
    page: /^\/templates\/[a-z0-9-]+\/[a-z0-9-]+\/?$/,
    target: 'template-contents',
    title: 'What a project is made of',
    body: 'Every Flow project has four parts: a Board with tasks, Agents that do the work, Workflows that tell agents what to do, and Triggers that start workflows on their own.',
    advance: 'next',
    side: 'right',
  },
  {
    id: 'A4',
    page: /^\/templates\/[a-z0-9-]+\/[a-z0-9-]+\/?$/,
    target: 'template-install',
    title: 'Install it',
    body: 'Install puts this template into a project. Click it.',
    advance: 'click',
    side: 'left',
  },
  {
    id: 'A5',
    page: /^\/company\/template_installs\/new/,
    target: 'install-submit',
    title: 'A project of its own',
    body: 'Templates install into a project: a separate workspace with its own board, agents and settings. This one gets a new project.',
    advance: 'click',
    side: 'top',
  },
  {
    id: 'A6',
    page: /^\/company\/projects\/\d+\/template_installs\/\d+/,
    target: 'setup-checklist',
    title: 'The setup checklist',
    body: 'This checklist shows what a template still needs: secrets, integrations, and triggers to switch on. Triggers start inactive, so nothing runs without you.',
    advance: 'next',
    goTo: (ctx) => project(ctx, '/overview'),
  },
  {
    id: 'A7',
    page: IN_PROJECT,
    target: 'project-nav-work',
    title: 'Your project',
    body: '<b>Work</b> is where things happen: tasks, workflows, triggers, runs and results. <b>Resources</b>, below it, is what agents use: agents, skills, connectors, repositories.',
    advance: 'next',
    side: 'right',
    goTo: (ctx) => project(ctx, '/workflows'),
  },
  {
    id: 'A8',
    page: /^\/company\/projects\/\d+\/workflows\/?$/,
    target: 'workflow-card',
    title: 'A workflow',
    body: 'A workflow is a chain of steps. Each step is an instruction that an agent carries out.',
    advance: 'next',
  },
  {
    id: 'A9',
    page: /^\/company\/projects\/\d+\/workflows\/?$/,
    target: 'workflow-run',
    title: 'Run it',
    body: 'You can start a workflow manually, like now, or let a trigger start it for you. Run it.',
    advance: 'click',
    skip: (ctx) => !ctx.hasAgent,
  },
  {
    id: 'A9-no-agent',
    page: /^\/company\/projects\/\d+\/workflows\/?$/,
    title: 'Connect an agent first',
    body: 'Workflows are carried out by an AI agent, and you have not connected one yet. Connect one in My Profile, then start the tour again from the menu under your name.',
    advance: 'next',
    skip: (ctx) => ctx.hasAgent,
    goTo: () => '/profile',
  },
  {
    id: 'A10',
    page: /^\/company\/projects\/\d+\/workflows\/?$/,
    target: 'run-drawer-submit',
    title: 'Start the run',
    body: 'Here you can pick the model, the runner and repositories for this run. The defaults are fine.',
    advance: 'click',
    side: 'top',
    skip: (ctx) => !ctx.hasAgent,
  },
  {
    id: 'A11',
    page: /^\/company\/projects\/\d+\/workflow_runs\/\d+/,
    target: 'run-sessions',
    title: 'A run and its sessions',
    body: 'This is a <b>run</b>. Each step runs as a <b>session</b>: an agent working in its own container.',
    advance: 'next',
    side: 'right',
  },
  {
    id: 'A12',
    page: /^\/company\/projects\/\d+\/workflow_runs\/\d+/,
    target: 'run-console',
    title: 'Watch the agent',
    body: 'Watch the agent work live. If a run fails, this is where you find out why.',
    advance: 'next',
    optionalTarget: true,
    side: 'left',
  },
  {
    id: 'A13',
    page: /^\/company\/projects\/\d+\/workflow_runs\/\d+/,
    target: 'run-assets-tab',
    title: 'Results',
    body: 'When the run finishes, its results appear here as <b>assets</b>. It takes a minute or two — meanwhile, let’s look at the board.',
    advance: 'next',
    goTo: (ctx) => project(ctx, '/board'),
  },
  {
    id: 'A14',
    page: /^\/company\/projects\/\d+\/board/,
    target: 'board',
    title: 'Board and triggers',
    body: 'In real work you rarely press Run. You move a card into a column, and its trigger starts the workflow. Switch the trigger on in <b>Triggers</b> to try it.',
    advance: 'next',
  },
  {
    id: 'A15',
    page: IN_PROJECT,
    title: "That's Flow",
    body: 'A board with tasks, workflows run by agents, triggers that start them, and results in assets. Next: install another template or describe your own process in <b>AI Builder</b>.',
    advance: 'next',
  },
];

// Scenario chapter B: a viewer can neither install nor run, so the tour only shows where to look.
const VIEWER: TourStep[] = [
  {
    id: 'B1',
    page: PROJECTS,
    target: 'project-card',
    title: 'Your projects',
    body: 'Everything in Flow lives in a project. Open one.',
    advance: 'click',
  },
  {
    id: 'B2',
    page: IN_PROJECT,
    target: 'project-nav-work',
    title: 'Where the work is',
    body: '<b>Tasks</b> is the project board. <b>Sessions & Runs</b> shows what agents are doing and have done.',
    advance: 'next',
    side: 'right',
    goTo: (ctx) => project(ctx, '/board'),
  },
  {
    id: 'B3',
    page: /^\/company\/projects\/\d+\/board/,
    target: 'board',
    title: 'The board',
    body: 'Tasks move across columns. A column can have a trigger that starts a workflow when a card lands in it.',
    advance: 'next',
    goTo: (ctx) => project(ctx, '/sessions'),
  },
  {
    id: 'B4',
    page: /^\/company\/projects\/\d+\/sessions/,
    title: 'Runs and sessions',
    body: 'Every run and every agent session is listed here. Ask an admin to give you edit access to run workflows yourself.',
    advance: 'next',
  },
];

export const CHAPTERS: Record<TourChapter, TourStep[]> = { 'first-run': FIRST_RUN, viewer: VIEWER };
