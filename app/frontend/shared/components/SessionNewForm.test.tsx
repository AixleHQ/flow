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
function authProps(
  configuredAgents: ('claude_code' | 'cursor_cli' | 'codex' | 'gemini_cli' | 'antigravity_cli' | 'grok')[] = [],
) {
  return { currentUser: buildSharedUser({ configuredAgents }) };
}

describe('SessionNewForm', () => {
  it('renders the agent runtime options and disables Start until a configured agent is chosen', () => {
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps([]) });

    // All six runtimes are shown.
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();
    expect(screen.getByText('Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();
    expect(screen.getByText('Antigravity CLI')).toBeInTheDocument();
    expect(screen.getByText('Grok')).toBeInTheDocument();

    // With no configured agents, every runtime tile is marked as needing setup.
    expect(screen.getAllByText('Setup')).toHaveLength(6);

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

    expect((await screen.findAllByText('Quota exceeded')).length).toBeGreaterThanOrEqual(1);
    expect(router.visit).not.toHaveBeenCalled();

    fetchSpy.mockRestore();
  });

  it('shows a per-server Connect CTA when the OAuth preflight blocks the launch (422)', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: false,
      status: 422,
      json: () =>
        Promise.resolve({
          error: 'Connect required for 1 OAuth MCP server(s) before launching',
          reauth_required: [{ mcp_server_id: 5, name: 'Sentry', connect_url: '/oauth/mcp/5/connect' }],
        }),
    } as Response);

    renderAuthedPage(<SessionNewForm {...makeProps({ projectId: 1 })} />, { props: authProps(['claude_code']) });

    await user.click(screen.getByText('Claude Code'));
    await user.click(screen.getByRole('button', { name: /start session/i }));

    // A Connect button per unconnected server — not a raw error, and no navigation.
    expect(await screen.findByRole('button', { name: 'Connect Sentry' })).toBeInTheDocument();
    expect(router.visit).not.toHaveBeenCalled();

    fetchSpy.mockRestore();
  });

  it('requires a prompt in automatic mode: Start stays disabled until text is entered', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['claude_code']) });

    await user.click(screen.getByText('Claude Code'));
    // Switch to Automatic (non_interactive) execution mode.
    await user.click(screen.getByRole('radio', { name: /Automatic/ }));

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
  it('does not render the secrets picker when the project has no config items', () => {
    renderAuthedPage(<SessionNewForm {...makeProps()} />, { props: authProps(['claude_code']) });

    expect(screen.queryByRole('combobox', { name: /secrets and variables/i })).not.toBeInTheDocument();
  });

  it('marks secrets in the picker so a secret reads differently from a variable', async () => {
    const user = userEvent.setup();
    renderAuthedPage(
      <SessionNewForm
        {...makeProps({
          projectId: 1,
          configItems: [
            { id: 7, name: 'STRIPE_KEY', itemType: 'secret' },
            { id: 8, name: 'API_BASE', itemType: 'variable' },
          ],
        })}
      />,
      { props: authProps(['claude_code']) },
    );

    const picker = screen.getByRole('combobox', { name: /secrets and variables/i });
    await user.click(picker);

    // A secret is labelled as such: attaching one is a different decision.
    expect(await screen.findByText('STRIPE_KEY (secret)')).toBeInTheDocument();
    expect(screen.getByText('API_BASE')).toBeInTheDocument();
  });

  it('sends the selected config item ids with the session', async () => {
    const user = userEvent.setup();
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: { id: 'sess-9' } }),
    } as Response);

    renderAuthedPage(
      <SessionNewForm
        {...makeProps({ projectId: 3, configItems: [{ id: 7, name: 'STRIPE_KEY', itemType: 'secret' }] })}
      />,
      { props: authProps(['claude_code']) },
    );

    await user.click(screen.getByText('Claude Code'));
    await user.click(screen.getByRole('combobox', { name: /secrets and variables/i }));
    await user.click(await screen.findByText('STRIPE_KEY (secret)'));
    await user.click(screen.getByRole('button', { name: /start session/i }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    const [, init] = fetchSpy.mock.calls[0];
    expect(JSON.parse(init!.body as string).terminalSession.configItemIds).toEqual([7]);

    fetchSpy.mockRestore();
  });
});
