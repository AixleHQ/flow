import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import LandingPage from './LandingPage';

const project = { id: 7, name: 'Workflow Robot' };

const session = (overrides: Record<string, unknown> = {}) => ({
  id: 101,
  state: 'finished',
  agentType: 'claude_code',
  createdAt: '2026-06-01T00:00:00Z',
  startedAt: '2026-06-01T00:00:00Z',
  finishedAt: '2026-06-01T01:00:00Z',
  ...overrides,
});

const baseProps = {
  project,
  sessions: [],
  activeSessionId: null,
  configuredAgents: [],
  assets: [],
};

describe('Projects/AixleBuilder/LandingPage', () => {
  it('renders the builder intro and warns when no agent runtimes are configured', () => {
    renderAuthedPage(<LandingPage />, { props: { ...baseProps } });

    expect(screen.getByText('Aixle Builder')).toBeInTheDocument();
    expect(screen.getByText(/No agent runtimes configured/i)).toBeInTheDocument();

    // With no runtime configured, the Start Builder button is disabled.
    expect(screen.getByRole('button', { name: /Start Builder/i })).toBeDisabled();
  });

  it('starts a builder session via router.post when an agent runtime is configured', async () => {
    renderAuthedPage(<LandingPage />, {
      props: { ...baseProps, configuredAgents: ['claude_code'] },
    });

    const startButton = screen.getByRole('button', { name: /Start Builder/i });
    expect(startButton).toBeEnabled();

    await userEvent.click(startButton);

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/aixle_builder/start',
      expect.objectContaining({ agentRuntime: 'claude_code' }),
      expect.any(Object),
    );
  });

  it('offers to continue an active session and navigates on click', async () => {
    renderAuthedPage(<LandingPage />, {
      props: { ...baseProps, configuredAgents: ['claude_code'], activeSessionId: 555 },
    });

    const continueButton = screen.getByRole('button', { name: /Continue Active Session/i });
    expect(continueButton).toBeInTheDocument();

    await userEvent.click(continueButton);

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder/555/session');
  });

  it('lists previous sessions and opens one via router.visit', async () => {
    renderAuthedPage(<LandingPage />, {
      props: {
        ...baseProps,
        configuredAgents: ['claude_code'],
        sessions: [session({ id: 101 })],
      },
    });

    expect(screen.getByText('Previous Sessions')).toBeInTheDocument();
    const table = screen.getByRole('table');
    expect(within(table).getByText('#101')).toBeInTheDocument();
    expect(within(table).getByText('finished')).toBeInTheDocument();

    await userEvent.click(within(table).getByRole('button'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder/101/session');
  });
});
