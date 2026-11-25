import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  companyProductTourPath,
  companyProjectBoardPath,
  companyProjectWorkflowRunPath,
  companyProjectsPath,
  statusCompanyProjectWorkflowRunPath,
} from 'shared/routes';
import { answerFetch } from 'test/fetchStub';
import { act, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { Highlight } from './highlighter';
import { ProductTourProvider, type TourPage, useProductTour } from './ProductTourProvider';
import { HELLO_FLOW_CARD } from './tours';
import type { StoredTour } from './tourStorage';

const highlighter = { show: vi.fn<(highlight: Highlight) => void>(), clear: vi.fn() };

const lastShown = () => highlighter.show.mock.lastCall?.[0];

const tourPage = (component: string, props: Record<string, unknown> = {}): TourPage => ({
  component,
  props: {
    features: { productTour: true },
    currentUser: { configuredAgents: ['claude_code'] },
    projects: [{ id: 7 }],
    ...props,
  },
});

const navigate = (page: TourPage) => {
  const listener = vi
    .mocked(router.on)
    .mock.calls.filter(([name]) => name === 'navigate')
    .at(-1)?.[1] as unknown as (event: unknown) => void;
  act(() => listener({ detail: { page } }));
};

const storeTour = (tour: Partial<StoredTour>) =>
  sessionStorage.setItem(
    'product-tour',
    JSON.stringify({
      tour: { variant: 'a', stepId: 'a1', projectId: null, runId: null, resumedFromToast: false, ...tour },
      watched: null,
    }),
  );

const storedTour = () => JSON.parse(sessionStorage.getItem('product-tour') ?? '{}').tour as StoredTour | undefined;

function Starter() {
  const { start, skip } = useProductTour();
  return (
    <>
      <button type="button" onClick={() => start('a')}>
        start tour
      </button>
      <button type="button" onClick={skip}>
        skip tour
      </button>
    </>
  );
}

/** Stand-ins for the page elements the steps point at. */
function Targets({ keys }: { keys: string[] }) {
  return (
    <>
      {keys.map((key) => (
        <button key={key} type="button" data-tour={key}>
          {key}
        </button>
      ))}
    </>
  );
}

const renderTour = (page: TourPage, targets: string[] = [], options: { targetTimeoutMs?: number } = {}) =>
  renderPage(
    <ProductTourProvider
      initialPage={page}
      highlighter={highlighter}
      targetTimeoutMs={options.targetTimeoutMs ?? 0}
      pollIntervalMs={5}
    >
      <Starter />
      <Targets keys={targets} />
    </ProductTourProvider>,
  );

describe('ProductTourProvider', () => {
  beforeEach(() => sessionStorage.clear());
  afterEach(() => sessionStorage.clear());

  it('starts tour A on the projects page and points at Templates in the sidebar', async () => {
    renderTour(tourPage('Projects/IndexPage'), ['nav-templates']);

    await userEvent.click(screen.getByRole('button', { name: 'start tour' }));

    expect(router.visit).toHaveBeenCalledWith(companyProjectsPath());
    await waitFor(() => expect(lastShown()).toMatchObject({ title: 'Templates', interactive: true }));
    expect(lastShown()?.primary).toBeUndefined();
    expect(lastShown()?.actions.map((action) => action.label)).toEqual(['Skip tour']);
  });

  it('moves past a click step only when the click lands on the target and its page opens', async () => {
    storeTour({ stepId: 'a1' });
    renderTour(tourPage('Projects/IndexPage'), ['nav-templates', 'elsewhere', HELLO_FLOW_CARD]);
    await waitFor(() => expect(lastShown()?.title).toBe('Templates'));

    await userEvent.click(screen.getByRole('button', { name: 'elsewhere' }));
    navigate(tourPage('Templates/IndexPage'));
    expect(storedTour()?.stepId).toBe('a1');

    navigate(tourPage('Projects/IndexPage'));
    await waitFor(() => expect(highlighter.show).toHaveBeenCalledTimes(2));
    await userEvent.click(screen.getByRole('button', { name: 'nav-templates' }));
    navigate(tourPage('Templates/IndexPage'));

    await waitFor(() => expect(lastShown()?.title).toBe('Hello Flow'));
    expect(storedTour()?.stepId).toBe('a2');
  });

  it('follows a click that stays on the page, such as Run opening its drawer', async () => {
    storeTour({ stepId: 'a9', projectId: 5 });
    renderTour(tourPage('Projects/Workflows/WorkflowsPage'), ['workflow-run', 'run-drawer-submit']);
    await waitFor(() => expect(lastShown()?.title).toBe('Run it'));

    await userEvent.click(screen.getByRole('button', { name: 'workflow-run' }));

    await waitFor(() => expect(lastShown()?.title).toBe('Run options'));
  });

  it('points to agent setup instead of Run when no agent is connected', async () => {
    storeTour({ stepId: 'a9', projectId: 5 });
    renderTour(tourPage('Projects/Workflows/WorkflowsPage', { currentUser: { configuredAgents: [] } }), [
      'workflow-run',
    ]);

    await waitFor(() => expect(lastShown()?.title).toBe('Connect an agent to run'));
    expect(lastShown()?.primary?.label).toBe('Open profile');
  });

  it('picks the tour up after a click that loads a whole new page', async () => {
    storeTour({ stepId: 'a4' });
    const first = renderTour(tourPage('Templates/ShowPage'), ['template-install']);
    await waitFor(() => expect(lastShown()?.title).toBe('Install it'));

    await userEvent.click(screen.getByRole('button', { name: 'template-install' }));
    first.unmount();
    renderTour(tourPage('Templates/InstallPage'), ['install-form', 'install-submit']);

    await waitFor(() => expect(lastShown()?.title).toBe('A new project'));
    expect(storedTour()).toMatchObject({ stepId: 'a5' });
  });

  it('takes the installed project from the setup page and visits its overview on Next', async () => {
    storeTour({ stepId: 'a5' });
    renderTour(tourPage('Templates/InstallPage'), ['install-form', 'install-submit', 'setup-checklist']);
    await waitFor(() => expect(lastShown()?.title).toBe('A new project'));

    await userEvent.click(screen.getByRole('button', { name: 'install-submit' }));
    navigate(tourPage('Projects/TemplateInstalls/ShowPage', { project: { id: 42 } }));
    await waitFor(() => expect(lastShown()?.title).toBe('Set up checklist'));

    act(() => lastShown()?.primary?.onClick());

    expect(router.visit).toHaveBeenCalledWith(expect.stringMatching(/\/projects\/42\/overview$/));
    expect(storedTour()).toMatchObject({ stepId: 'a7', projectId: 42 });
  });

  it('resumes from the stored step after a reload', async () => {
    storeTour({ stepId: 'a3' });

    renderTour(tourPage('Templates/ShowPage'), ['template-parts']);

    await waitFor(() => expect(lastShown()?.title).toBe('What a project is made of'));
  });

  it('offers to skip or end when a target never appears, rather than hanging', async () => {
    storeTour({ stepId: 'a8', projectId: 5 });

    renderTour(tourPage('Projects/Workflows/WorkflowsPage'));

    await waitFor(() => expect(lastShown()?.title).toBe('Workflows'));
    expect(lastShown()?.element).toBeUndefined();
    expect(lastShown()?.actions.map((action) => action.label)).toEqual(['End tour', 'Skip this step']);
  });

  it('records the tour as finished when it is skipped', async () => {
    const fetchSpy = answerFetch({ [`PATCH ${companyProductTourPath()}`]: new Response(null, { status: 204 }) });
    storeTour({ stepId: 'a3' });
    renderTour(tourPage('Templates/ShowPage'), ['template-parts']);
    await waitFor(() => expect(lastShown()?.title).toBe('What a project is made of'));

    act(() => lastShown()?.actions.find((action) => action.label === 'Skip tour')?.onClick());

    expect(highlighter.clear).toHaveBeenCalled();
    expect(storedTour()).toBeUndefined();
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        companyProductTourPath(),
        expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ variant: 'a' }) }),
      ),
    );
  });

  it('sends the member to the board while the run goes on and tells them when it has finished', async () => {
    let polls = 0;
    answerFetch({
      [`GET ${statusCompanyProjectWorkflowRunPath(5, 9)}`]: () => {
        polls += 1;
        return { id: 9, state: polls < 3 ? 'running' : 'completed', finished: polls >= 3 };
      },
    });
    storeTour({ stepId: 'a13', projectId: 5, runId: 9 });
    renderTour(tourPage('Projects/WorkflowRuns/ShowPage', { project: { id: 5 }, run: { id: 9 } }), [
      'run-assets-tab',
    ]);

    await waitFor(() => expect(lastShown()?.description).toMatch(/It takes ~1–2 min/));
    act(() => lastShown()?.primary?.onClick());
    expect(router.visit).toHaveBeenCalledWith(companyProjectBoardPath(5));
    expect(storedTour()?.stepId).toBe('a14');

    const seeResult = await screen.findByRole('button', { name: 'See the result' });
    expect(screen.getByText('Your first run finished')).toBeInTheDocument();
    await userEvent.click(seeResult);

    expect(router.visit).toHaveBeenCalledWith(companyProjectWorkflowRunPath(5, 9));
    expect(storedTour()).toMatchObject({ stepId: 'a13', resumedFromToast: true });
  });

  it('ends after a failed run instead of showing the board', async () => {
    answerFetch({ [`GET ${statusCompanyProjectWorkflowRunPath(5, 9)}`]: { id: 9, state: 'failed', finished: true } });
    storeTour({ stepId: 'a13', projectId: 5, runId: 9 });
    renderTour(tourPage('Projects/WorkflowRuns/ShowPage'), ['run-assets-tab']);

    await waitFor(() => expect(lastShown()?.description).toBe('This run failed. Open Sessions & Runs to see why.'));
    act(() => lastShown()?.primary?.onClick());

    expect(storedTour()?.stepId).toBe('a15');
  });

  it('runs tour B from the projects to the first project board', async () => {
    storeTour({ variant: 'b', stepId: 'b1' });
    renderTour(tourPage('Projects/IndexPage'), ['projects-list']);
    await waitFor(() => expect(lastShown()?.title).toBe('Projects'));

    act(() => lastShown()?.primary?.onClick());

    expect(router.visit).toHaveBeenCalledWith(companyProjectBoardPath(7));
    expect(storedTour()?.stepId).toBe('b2');
  });

  it('goes straight to the closing words when a viewer sees no project', async () => {
    storeTour({ variant: 'b', stepId: 'b1' });
    renderTour(tourPage('Projects/IndexPage', { projects: [] }));
    await waitFor(() => expect(lastShown()?.title).toBe('Projects'));

    act(() => lastShown()?.actions.find((action) => action.label === 'Skip this step')?.onClick());

    await waitFor(() => expect(lastShown()?.description).toMatch(/Ask an admin to give you edit access/));
  });

  it('shows nothing while the product tour flag is off', async () => {
    storeTour({ stepId: 'a3' });

    renderTour({ component: 'Templates/ShowPage', props: { features: { productTour: false } } }, ['template-parts']);

    await waitFor(() => expect(highlighter.clear).toHaveBeenCalled());
    expect(highlighter.show).not.toHaveBeenCalled();
  });
});
