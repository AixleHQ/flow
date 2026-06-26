import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { buildSharedUser } from 'test/factories/sharedProps';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { SessionNewForm, type SessionNewFormProps } from './SessionNewForm';

function makeProps(overrides: Partial<SessionNewFormProps> = {}): SessionNewFormProps {
  return {
    onCreatedPath: (id, projectId) => `/sessions/${id}?project=${projectId}`,
    fallbackPath: '/fallback',
    ...overrides,
  };
}

// Seed SharedProps with a currentUser whose configured agents we control.
function authProps(configuredAgents: ('claude_code' | 'cursor_cli' | 'codex' | 'gemini_cli')[] = []) {
  return { currentUser: buildSharedUser({ configuredAgents }) };
}

describe('SessionNewForm', () => {
  it('renders the agent runtime options and disables Start until a configured agent is chosen', () => {
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps([]) });

    // All four runtimes are shown.
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();
    expect(screen.getByText('Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();

    // With no configured agents, every card shows a "Setup needed" badge.
    expect(screen.getAllByText('Setup needed')).toHaveLength(4);

    // Start is disabled because no agent can be selected.
    expect(screen.getByRole('button', { name: /start session/i })).toBeDisabled();
  });

  it('enables Start after selecting a configured agent in interactive mode', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['claude_code']) });

    const startBtn = screen.getByRole('button', { name: /start session/i });
    expect(startBtn).toBeDisabled();

    await user.click(screen.getByText('Claude Code'));

    expect(startBtn).toBeEnabled();
  });

  it('does NOT submit when no agent is selected (click on a disabled control is a no-op)', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['claude_code']) });

    // Button is disabled; clicking must not fire a request or navigation.
    await user.click(screen.getByRole('button', { name: /start session/i }));

    expect(fetchSpy).not.toHaveBeenCalled();
    expect(router.visit).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it('posts a session and navigates via onCreatedPath on success', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: { id: 'sess-77' } }),
    } as Response);

    const onCreatedPath = vi.fn((id: string) => `/sessions/${id}`);
    renderAuthedPage(<SessionNewForm {...makeProps({ projectId: 42, onCreatedPath })} />, {
      props: authProps(['claude_code']),
    });

    await user.click(screen.getByText('Claude Code'));
    await user.click(screen.getByRole('button', { name: /start session/i }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());

    // The POST body carries the chosen runtime and the fixed project id.
    const [, init] = fetchSpy.mock.calls[0];
    expect(init?.method).toBe('POST');
    const body = JSON.parse(init!.body as string);
    expect(body.terminalSession.agentType).toBe('claude_code');
    expect(body.terminalSession.projectId).toBe(42);

    await waitFor(() => expect(router.visit).toHaveBeenCalledWith('/sessions/sess-77'));
    expect(onCreatedPath).toHaveBeenCalledWith('sess-77', 42);

    fetchSpy.mockRestore();
  });

  it('shows a server error message and does not navigate when the request fails', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ errors: ['Quota exceeded'] }),
    } as Response);

    renderAuthedPage(<SessionNewForm {...makeProps({ projectId: 1 })} />, { props: authProps(['codex']) });

    await user.click(screen.getByText('Codex'));
    await user.click(screen.getByRole('button', { name: /start session/i }));

    await waitFor(() => expect(screen.getByText('Quota exceeded')).toBeInTheDocument());
    expect(router.visit).not.toHaveBeenCalled();

    fetchSpy.mockRestore();
  });

  it('requires a prompt in automatic mode: Start stays disabled until text is entered', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['claude_code']) });

    await user.click(screen.getByText('Claude Code'));
    // Switch to Automatic (non_interactive) execution mode.
    await user.click(screen.getByRole('radio', { name: 'Automatic' }));

    const startBtn = screen.getByRole('button', { name: /start session/i });
    expect(startBtn).toBeDisabled();

    const prompt = screen.getByRole('textbox', { name: /initial prompt/i });
    await user.type(prompt, 'Refactor the auth module');

    expect(startBtn).toBeEnabled();
  });

  it('renders a session summary badge reflecting the selected agent and mode', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['gemini_cli']) });

    await user.click(screen.getByText('Gemini CLI'));

    const summary = screen.getByText('Session Summary').closest('div')!;
    expect(within(summary.parentElement as HTMLElement).getByText('Interactive')).toBeInTheDocument();
  });
});
