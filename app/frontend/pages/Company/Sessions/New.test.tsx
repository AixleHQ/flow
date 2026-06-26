import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';
import { buildSharedUser } from 'test/factories/sharedProps';
import New from './New';

// A user with one configured agent runtime so the agent card becomes selectable
// and canSubmit can flip true once it is picked.
const configuredUser = buildSharedUser({ configuredAgents: ['claude_code'] });

describe('Company/Sessions/New', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('renders the New Session header and the agent runtime options', () => {
    renderAuthedPage(<New />, { props: { projects: [], preSelectedProjectId: null } });

    expect(screen.getByText('New Session')).toBeInTheDocument();
    expect(screen.getByText('Agent Runtime')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();

    // configuredAgents defaults to [] so no runtime is selectable and Start stays disabled.
    expect(screen.getByRole('button', { name: /Start Session/i })).toBeDisabled();
  });

  it('navigates back to the sessions list when Back is clicked', async () => {
    renderAuthedPage(<New />, { props: { projects: [], preSelectedProjectId: null } });

    await userEvent.click(screen.getByRole('button', { name: /Back/i }));

    expect(router.visit).toHaveBeenCalledWith('/company/sessions');
  });

  it('enables Start and shows the session summary once a configured runtime is selected', async () => {
    renderAuthedPage(<New />, {
      props: { projects: [], preSelectedProjectId: null, currentUser: configuredUser },
    });

    const startButton = screen.getByRole('button', { name: /Start Session/i });
    expect(startButton).toBeDisabled();

    await userEvent.click(screen.getByText('Claude Code'));

    expect(startButton).toBeEnabled();
    expect(screen.getByText('Session Summary')).toBeInTheDocument();
  });

  it('posts to the sessions API and navigates to the created session on success', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { id: '88' } }),
    });
    vi.stubGlobal('fetch', fetchMock);

    renderAuthedPage(<New />, {
      props: { projects: [], preSelectedProjectId: null, currentUser: configuredUser },
    });

    await userEvent.click(screen.getByText('Claude Code'));
    await userEvent.click(screen.getByRole('button', { name: /Start Session/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalled());

    const [, init] = fetchMock.mock.calls[0];
    expect(init.method).toBe('POST');
    const body = JSON.parse(init.body as string);
    expect(body.terminalSession.agentType).toBe('claude_code');
    expect(body.terminalSession.sessionType).toBe('agent_session');

    await waitFor(() => expect(router.visit).toHaveBeenCalledWith('/company/sessions/88'));
  });
});
