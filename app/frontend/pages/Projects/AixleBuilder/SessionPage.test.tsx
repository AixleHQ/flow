import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import SessionPage from './SessionPage';

const project = { id: 7, name: 'Phoenix' };

const baseSession = {
  id: 42,
  state: 'ready',
  agentType: 'claude_code',
  mode: 'plan',
  websocketUrl: null,
  ideUrl: null,
  createdAt: '2026-06-26 10:00:00 UTC',
  startedAt: '2026-06-26 10:01:00 UTC',
  finishedAt: null,
  errorMessage: null,
};

describe('Projects/AixleBuilder/SessionPage', () => {
  it('renders the active session header with the resolved agent label and a Finish action', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Aixle Builder')).toBeInTheDocument();
    expect(screen.getByText('#42')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Finish Session' })).toBeInTheDocument();
  });

  it('fires router.post to the finish endpoint when Finish Session is clicked', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Finish Session' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/aixle_builder/42/finish',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the empty activity state when there is no builder activity', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(await screen.findByText('No builder activity yet')).toBeInTheDocument();
  });

  it('renders seeded workflows after switching to the Workflows tab', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [{ id: 1, name: 'Triage Inbound', description: 'Sort new requests', stepsCount: 4 }],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: /Workflows/ }));

    const workflow = await screen.findByText('Triage Inbound');
    expect(workflow).toBeInTheDocument();
    expect(screen.getByText('4 steps')).toBeInTheDocument();
  });

  it('renders the ended state with navigation buttons for a finished session', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'finished' },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByRole('button', { name: 'Back to Builder' })).toBeInTheDocument();
    const startNew = screen.getByRole('button', { name: 'Start New Build' });

    await userEvent.click(startNew);
    await waitFor(() => expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder'));
  });

  it('falls back to the raw agentType when it is not a known label', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, agentType: 'mystery_agent' },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('mystery_agent')).toBeInTheDocument();
  });

  it('shows an em dash for the agent when agentType is null', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, agentType: null },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('—')).toBeInTheDocument();
  });

  it('renders the Live badge and a Finish action for an active session with a cable stream', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'running' },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Live')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Finish Session' })).toBeInTheDocument();
  });

  it('shows the starting-container loader and the current state badge while active without a terminal', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'running', websocketUrl: null },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Starting container...')).toBeInTheDocument();
  });

  it('hides the main panel empty state while the finishing overlay is shown', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: {
          ...baseSession,
          state: 'finishing',
          websocketUrl: null,
          errorMessage: 'Container exited unexpectedly',
        },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.queryByText('Session finishing')).not.toBeInTheDocument();
    expect(screen.queryByText('Container exited unexpectedly')).not.toBeInTheDocument();
  });

  it('shows the finishing overlay when the session state is finishing', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'finishing', websocketUrl: null },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Finishing session…')).toBeInTheDocument();
  });

  it('shows the finishing overlay after clicking Finish Session on an active session', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'running' },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Finish Session' }));

    expect(await screen.findByText('Finishing session…')).toBeInTheDocument();
  });

  it('renders an activity row with its action label and entity name', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [
          {
            action: 'created_workflow',
            entityType: 'Workflow',
            entityName: 'Onboarding Pipeline',
            entityId: 11,
            timestamp: '2026-06-26 10:05:00 UTC',
          },
        ],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Onboarding Pipeline')).toBeInTheDocument();
    expect(screen.getByText('Created workflow')).toBeInTheDocument();
  });

  it('falls back to the raw action string for an unmapped activity action', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [
          {
            action: 'some_unmapped_action',
            entityType: 'Tool',
            entityName: 'Mailer',
            timestamp: '2026-06-26 10:06:00 UTC',
          },
        ],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('some_unmapped_action')).toBeInTheDocument();
    expect(screen.getByText('Mailer')).toBeInTheDocument();
  });

  it('shows the activity count in the Activity tab label when activities are present', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [
          { action: 'created_step', entityType: 'Step', entityName: 'Collect', timestamp: '2026-06-26 10:05:00 UTC' },
          { action: 'created_agent', entityType: 'Agent', entityName: 'Helper', timestamp: '2026-06-26 10:06:00 UTC' },
        ],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByRole('tab', { name: /Activity \(2\)/ })).toBeInTheDocument();
  });

  it('renders the empty workflows state after switching to the Workflows tab with none seeded', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: /Workflows/ }));

    expect(await screen.findByText('No workflows created yet')).toBeInTheDocument();
  });

  it('renders board columns with an auto-trigger binding after switching to the Board tab', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [
          {
            id: 3,
            name: 'In Review',
            purpose: 'Items awaiting approval',
            workflowBinding: { workflowName: 'Approve Items', triggerMode: 'auto' },
          },
        ],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: 'Board' }));

    expect(await screen.findByText('In Review')).toBeInTheDocument();
    expect(screen.getByText('Items awaiting approval')).toBeInTheDocument();
    expect(screen.getByText(/Approve Items/)).toBeInTheDocument();
  });

  it('renders the empty board state after switching to the Board tab with no columns', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: 'Board' }));

    expect(await screen.findByText('No board configured yet')).toBeInTheDocument();
  });

  it('renders the failed ended state with its error message', () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: { ...baseSession, state: 'failed', errorMessage: 'Build crashed' },
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    expect(screen.getByText('Session failed')).toBeInTheDocument();
    expect(screen.getByText('Build crashed')).toBeInTheDocument();
  });

  it('navigates back to the builder list when the header Back button is clicked', async () => {
    renderAuthedPage(<SessionPage />, {
      props: {
        project,
        session: baseSession,
        cableStream: 'signed-stream',
        builderActivities: [],
        workflows: [],
        boardColumns: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Back/ }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder');
  });
});
