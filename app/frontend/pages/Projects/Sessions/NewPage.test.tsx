import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import NewPage from './NewPage';

const project = { id: 7, name: 'Orbital Lab' };

describe('Projects/Sessions/NewPage', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('renders the session form with the Start button disabled when no agent runtime is configured', () => {
    renderAuthedPage(<NewPage />, { props: { project } });

    expect(screen.getByText('Agent Runtime')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();

    const startButton = screen.getByRole('button', { name: /Start Session/i });
    expect(startButton).toBeInTheDocument();
    // configuredAgents defaults to [] so nothing is selectable and canSubmit is false.
    expect(startButton).toBeDisabled();
  });

  it('enables the Start button and shows a summary once a configured agent runtime is picked', async () => {
    renderAuthedPage(<NewPage />, {
      props: {
        project,
        currentUser: {
          id: 1,
          email: 'pilot@example.com',
          name: 'Pilot User',
          role: 'admin',
          state: 'active',
          position: null,
          preferredAgentLanguage: 'en',
          selectedAgents: [],
          onboardingState: 'completed',
          onboardingCompletedAt: '2026-01-01T00:00:00Z',
          defaultAgentCredentialId: null,
          defaultAgentRuntime: null,
          configuredAgents: ['claude_code'],
          agentCredentials: [],
          company: {
            id: 1,
            name: 'Test Company',
            emailDomain: 'example.com',
            logoUrl: null,
            primaryColor: null,
            secondaryColor: null,
          },
        },
      },
    });

    const startButton = screen.getByRole('button', { name: /Start Session/i });
    expect(startButton).toBeDisabled();

    await userEvent.click(screen.getByText('Claude Code'));

    expect(startButton).toBeEnabled();

    // The summary card surfaces the chosen runtime once an agent is selected.
    expect(screen.getByText('Session Summary')).toBeInTheDocument();
  });

  it('reveals the prompt field in Automatic mode and keeps Start disabled until a prompt is entered', async () => {
    renderAuthedPage(<NewPage />, {
      props: {
        project,
        currentUser: {
          id: 1,
          email: 'pilot@example.com',
          name: 'Pilot User',
          role: 'admin',
          state: 'active',
          position: null,
          preferredAgentLanguage: 'en',
          selectedAgents: [],
          onboardingState: 'completed',
          onboardingCompletedAt: '2026-01-01T00:00:00Z',
          defaultAgentCredentialId: null,
          defaultAgentRuntime: null,
          configuredAgents: ['claude_code'],
          agentCredentials: [],
          company: {
            id: 1,
            name: 'Test Company',
            emailDomain: 'example.com',
            logoUrl: null,
            primaryColor: null,
            secondaryColor: null,
          },
        },
      },
    });

    await userEvent.click(screen.getByText('Claude Code'));
    const startButton = screen.getByRole('button', { name: /Start Session/i });
    expect(startButton).toBeEnabled();

    // Switching to Automatic requires a prompt before the session can start.
    await userEvent.click(screen.getByRole('radio', { name: 'Automatic' }));
    expect(screen.getByPlaceholderText('Describe the task for the agent...')).toBeInTheDocument();
    expect(startButton).toBeDisabled();

    await userEvent.type(screen.getByPlaceholderText('Describe the task for the agent...'), 'Refactor the auth module');
    expect(startButton).toBeEnabled();
  });

  it('posts to the sessions API and navigates to the created session on success', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { id: '42' } }),
    });
    vi.stubGlobal('fetch', fetchMock);

    renderAuthedPage(<NewPage />, {
      props: {
        project,
        currentUser: {
          id: 1,
          email: 'pilot@example.com',
          name: 'Pilot User',
          role: 'admin',
          state: 'active',
          position: null,
          preferredAgentLanguage: 'en',
          selectedAgents: [],
          onboardingState: 'completed',
          onboardingCompletedAt: '2026-01-01T00:00:00Z',
          defaultAgentCredentialId: null,
          defaultAgentRuntime: null,
          configuredAgents: ['claude_code'],
          agentCredentials: [],
          company: {
            id: 1,
            name: 'Test Company',
            emailDomain: 'example.com',
            logoUrl: null,
            primaryColor: null,
            secondaryColor: null,
          },
        },
      },
    });

    await userEvent.click(screen.getByText('Claude Code'));
    await userEvent.click(screen.getByRole('button', { name: /Start Session/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());

    const [, init] = fetchMock.mock.calls[0];
    expect(init.method).toBe('POST');
    const body = JSON.parse(init.body as string);
    expect(body.terminalSession.agentType).toBe('claude_code');
    expect(body.terminalSession.projectId).toBe(7);

    await waitFor(() => expect(router.visit).toHaveBeenCalledWith('/company/projects/7/sessions/42'));
  });
});
