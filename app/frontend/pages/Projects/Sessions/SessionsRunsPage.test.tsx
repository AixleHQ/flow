import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import SessionsRunsPage, { type ListEntry, type SessionsRunsPageProps } from './SessionsRunsPage';

const project = { id: 7, name: 'Falcon Project' };

function buildSessionEntry(overrides: Partial<ListEntry> = {}): ListEntry {
  return {
    id: 2009,
    kind: 'session',
    name: 'Refactor onboarding status chips',
    state: 'finished',
    sessionType: 'agent_session',
    agentType: 'claude_code',
    mode: 'interactive',
    totalTokens: 228_700,
    costCents: 17,
    startedAt: '2026-06-26T10:00:00Z',
    finishedAt: '2026-06-26T10:03:00Z',
    createdAt: '2026-06-26T09:59:00Z',
    userName: 'Artem Petrov',
    viewable: true,
    ...overrides,
  } as ListEntry;
}

function buildRunEntry(overrides: Partial<ListEntry> = {}): ListEntry {
  return {
    id: 1443,
    kind: 'run',
    name: 'Weekly GA report',
    state: 'completed',
    agentType: 'claude_code',
    mode: 'non_interactive',
    totalTokens: 4_700_000,
    costCents: 478,
    startedAt: '2026-06-23T10:00:00Z',
    completedAt: '2026-06-23T10:11:00Z',
    createdAt: '2026-06-23T09:59:00Z',
    userName: 'Artem Petrov',
    stepsCompleted: 1,
    stepsTotal: 1,
    sessions: [
      {
        id: 1986,
        kind: 'session',
        name: 'GA report — session #1986',
        state: 'finished',
        agentType: 'claude_code',
        mode: 'interactive',
        totalTokens: 4_700_000,
        costCents: 478,
        startedAt: '2026-06-23T10:00:00Z',
        finishedAt: '2026-06-23T10:11:00Z',
        createdAt: '2026-06-23T09:59:00Z',
        userName: 'Artem Petrov',
        viewable: true,
      },
    ],
    ...overrides,
  } as ListEntry;
}

// Inertia hands page props to the component; the harness only seeds usePage(),
// so page props are spread onto the element as well.
function seed(props: Partial<SessionsRunsPageProps> = {}): SessionsRunsPageProps {
  return {
    project,
    entries: [buildSessionEntry(), buildRunEntry()],
    filters: { type: 'all' as const },
    total: 2,
    userOptions: [{ id: 3, name: 'Artem Petrov' }],
    ...props,
  };
}

function renderWith(props: SessionsRunsPageProps) {
  return renderAuthedPage(<SessionsRunsPage {...props} />, { props: props as unknown as Record<string, unknown> });
}

describe('Projects/Sessions/SessionsRunsPage', () => {
  it('lists standalone sessions and workflow runs in one table', () => {
    renderWith(seed());

    expect(screen.getByRole('heading', { name: 'Sessions & Runs' })).toBeInTheDocument();
    expect(screen.getByText('Refactor onboarding status chips')).toBeInTheDocument();
    expect(screen.getByText('Weekly GA report')).toBeInTheDocument();
    // The kind is stated on the row rather than left to the reader to infer;
    // the sub-line reads "#id · kind [· n/m steps]".
    expect(screen.getByText(/#2009.*Standalone session/)).toBeInTheDocument();
    expect(screen.getByText(/#1443.*Run.*1\/1 steps/)).toBeInTheDocument();
    expect(screen.getByText('2 entries')).toBeInTheDocument();
  });

  it("keeps a run's sessions folded under it until the row is expanded", async () => {
    renderWith(seed());

    expect(screen.queryByText('GA report — session #1986')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /expand weekly ga report/i }));

    expect(screen.getByText('GA report — session #1986')).toBeInTheDocument();
  });

  it('does not offer an expander for a standalone session', () => {
    renderWith(seed({ entries: [buildSessionEntry()] }));

    expect(screen.queryByRole('button', { name: /expand/i })).not.toBeInTheDocument();
  });

  it('opens a row and links each row to its detail page', async () => {
    renderWith(seed());

    expect(screen.getByRole('link', { name: 'Open session #2009' })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions/2009',
    );
    expect(screen.getByRole('link', { name: 'Open run #1443' })).toHaveAttribute(
      'href',
      '/company/projects/7/workflow_runs/1443',
    );

    await userEvent.click(screen.getByText('Refactor onboarding status chips'));
    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/2009');
  });

  it('locks a row whose owner keeps that session private', () => {
    renderWith(seed({ entries: [buildSessionEntry({ viewable: false, name: 'Interactive session' })] }));

    expect(screen.getByLabelText('Session #2009 is private')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /open session/i })).not.toBeInTheDocument();
  });

  it('navigates with the chosen type when a type tab is clicked', async () => {
    renderWith(seed());

    await userEvent.click(screen.getByRole('tab', { name: 'Workflow runs' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      expect.objectContaining({ type: 'run' }),
      expect.objectContaining({ preserveState: true }),
    );
  });

  it('offers both create actions on the All tab', () => {
    renderWith(seed());

    expect(screen.getByRole('button', { name: /run workflow/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /new session/i })).toBeInTheDocument();
  });

  it('offers only Run workflow on the Workflow runs tab', () => {
    renderWith(seed({ filters: { type: 'run' } }));

    expect(screen.getByRole('button', { name: /run workflow/i })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /new session/i })).not.toBeInTheDocument();
  });

  it('offers only New Session on the Standalone tab', () => {
    renderWith(seed({ filters: { type: 'solo' } }));

    expect(screen.queryByRole('button', { name: /run workflow/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /new session/i })).toBeInTheDocument();
  });

  it('applies the agent filter through the query string', async () => {
    renderWith(seed());

    await userEvent.click(screen.getByPlaceholderText('Agent'));
    await userEvent.click(await screen.findByRole('option', { name: 'Codex' }));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/sessions',
      expect.objectContaining({ agent_type: 'codex' }),
      expect.anything(),
    );
  });

  it('says the project is empty when nothing has run in it', () => {
    renderWith(seed({ entries: [], total: 0 }));

    expect(screen.getByText('Nothing has run in this project yet.')).toBeInTheDocument();
  });

  it('says the filters matched nothing when a filter is applied', () => {
    renderWith(seed({ entries: [], total: 0, filters: { type: 'all', status: 'failed' } }));

    expect(screen.getByText('No sessions match these filters.')).toBeInTheDocument();
  });

  it('reports tokens, cost and duration in the data columns', () => {
    renderWith(seed({ entries: [buildRunEntry()] }));

    expect(screen.getByText('4.7M')).toBeInTheDocument();
    expect(screen.getByText('$4.78')).toBeInTheDocument();
    expect(screen.getByText('11m 0s')).toBeInTheDocument();
  });
});
