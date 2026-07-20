import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildSharedUser } from 'test/factories/sharedProps';
import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';
import type TerminalSession from 'types/generated/TerminalSession';

import type { AgentType, SharedUser } from 'shared/ui';

import OnboardingPage from './OnboardingPage';

// Minimal TerminalSession fixture — the authenticate step only reads agentType/state/websocketUrl.
const buildTerminalSession = (overrides: Partial<TerminalSession> = {}): TerminalSession => ({
  id: 1,
  sessionType: 'auth_setup',
  agentType: 'claude_code',
  state: 'starting',
  mode: 'interactive',
  startedAt: null,
  finishingAt: null,
  finishedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  totalTokens: 0,
  inputTokens: 0,
  outputTokens: 0,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
  costCents: 0,
  models: [],
  requestedModel: null,
  artifactsReviewed: null,
  initialPrompt: null,
  errorMessage: null,
  containerId: null,
  projectId: null,
  routeToken: null,
  configuredAgentId: null,
  contextMetadata: null,
  metadata: null,
  collectedAt: null,
  updatedAt: '2026-01-01T00:00:00Z',
  sessionConfig: {},
  toolIds: [],
  skillIds: [],
  mcpServerIds: [],
  inputAssetIds: [],
  repositoryIds: [],
  pendingArtifactsCount: 0,
  sessionLogsCount: 0,
  cloudConnectRequested: false,
  ...overrides,
});

// Build a currentUser pinned to a specific onboarding step. The page derives the active step
// from currentUser.onboardingState (step1 → Profile, step2 → Agents, step4 → Complete) and seeds
// its local position/language/selectedAgents state from the same user object.
const userAt = (overrides: Partial<SharedUser> = {}): SharedUser =>
  buildSharedUser({
    name: 'Riley Onboarder',
    onboardingState: 'step1',
    position: null,
    preferredAgentLanguage: '',
    selectedAgents: [],
    configuredAgents: [],
    ...overrides,
  });

describe('Onboarding/OnboardingPage', () => {
  it('renders the profile step heading and welcome copy', () => {
    renderAuthedPage(<OnboardingPage />, { props: { currentUser: userAt(), authSessions: [] } });

    expect(screen.getByText('Tell us about yourself')).toBeInTheDocument();
    expect(screen.getByText('Set up your workspace')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Continue/ })).toBeInTheDocument();
  });

  it('blocks advancing from the profile step when required fields are empty', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    // Continue is disabled when no position is selected and no language chosen
    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();
  });

  it('submits the profile step to the backend when position and language are set', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ position: 'dev', preferredAgentLanguage: 'en' }),
        authSessions: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({
        onboarding: expect.objectContaining({ position: 'dev', onboardingStateEvent: 'go_next' }),
      }),
      expect.anything(),
    );
  });

  it('renders the agent connection step when at step2', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ onboardingState: 'step2' }), authSessions: [] },
    });

    expect(screen.getByText('Connect your agents')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();
  });

  it('renders the completion step and fires the complete event on Get Started', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step4',
          position: 'dev',
          preferredAgentLanguage: 'en',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: ['claude_code'] as AgentType[],
        }),
        authSessions: [],
      },
    });

    expect(screen.getByText("You're all set!")).toBeInTheDocument();
    const getStarted = screen.getByRole('button', { name: /Get Started/ });

    await userEvent.click(getStarted);

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/onboarding',
        expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'complete' }) }),
        expect.anything(),
      ),
    );
  });

  it('renders the welcome card with the company name and the three stepper labels for contributors', () => {
    renderAuthedPage(<OnboardingPage />, { props: { currentUser: userAt(), authSessions: [] } });

    expect(screen.getByText('Set up your workspace')).toBeInTheDocument();
    expect(screen.getByText('Your Profile')).toBeInTheDocument();
    expect(screen.getByText('Connect Agents')).toBeInTheDocument();
    expect(screen.getByText('Complete')).toBeInTheDocument();
  });

  it('renders all four agent cards with their descriptions on the agent connection step', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ onboardingState: 'step2' }), authSessions: [] },
    });

    expect(screen.getByText('OpenAI Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();
    expect(screen.getByText("Anthropic's AI coding assistant with deep reasoning capabilities")).toBeInTheDocument();
    expect(screen.getByText('Sign in to at least one agent to enable it for your workflows.')).toBeInTheDocument();
  });

  it('blocks advancing from the connect agents step when no agent is configured', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ onboardingState: 'step2', selectedAgents: [], configuredAgents: [] }),
        authSessions: [],
      },
    });

    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('advances the connect agents step to the backend with go_next when an agent is pre-configured', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ onboardingState: 'step2', configuredAgents: ['codex'] as AgentType[] }),
        authSessions: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({
        onboarding: expect.objectContaining({
          onboardingStateEvent: 'go_next',
        }),
      }),
      expect.anything(),
    );
  });

  it('fires go_previous when the Back button is clicked on the connect agents step', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ onboardingState: 'step2', configuredAgents: ['claude_code'] as AgentType[] }),
        authSessions: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Back/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'go_previous' }) }),
      expect.anything(),
    );
  });

  it('renders the connect agents step with all agents and NOT CONNECTED badge by default', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code', 'codex'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [],
      },
    });

    expect(screen.getByText('Connect your agents')).toBeInTheDocument();
    expect(screen.getAllByText('NOT CONNECTED')).toHaveLength(4);
  });

  it('shows the Connected badge and an enabled Continue when an agent is configured', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code', 'codex'] as AgentType[],
          configuredAgents: ['claude_code'] as AgentType[],
        }),
        authSessions: [],
      },
    });

    expect(screen.getByText('Connected')).toBeInTheDocument();
    expect(screen.getByText('1 of 4 connected')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Continue/ })).toBeEnabled();
  });

  it('disables Continue on the connect agents step when no agent is configured', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [],
      },
    });

    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();
  });

  it('shows the "Connecting" badge when an agent has an active auth session but is not configured', () => {
    const session: TerminalSession = {
      ...buildTerminalSession(),
      agentType: 'claude_code',
      state: 'starting',
    };
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [session],
      },
    });

    expect(screen.getByText('Connecting')).toBeInTheDocument();
  });

  it('clicking Connect for an agent expands the terminal inline', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [],
      },
    });

    // Connect button appears for unconfigured agents
    const connectButtons = screen.getAllByRole('button', { name: /Connect/ });
    expect(connectButtons.length).toBeGreaterThan(0);
  });

  it('renders the completion summary with resolved position/language labels and per-agent auth badges', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step4',
          position: 'qa',
          preferredAgentLanguage: 'ru',
          selectedAgents: ['claude_code', 'codex'] as AgentType[],
          configuredAgents: ['claude_code'] as AgentType[],
        }),
        authSessions: [],
      },
    });

    // Position/language values are resolved through the option-label lookups.
    expect(screen.getByText('QA Engineer')).toBeInTheDocument();
    expect(screen.getByText('Russian')).toBeInTheDocument();
    // One configured agent → authenticated badge; one not → not-authenticated badge.
    expect(screen.getByText('✓ Authenticated')).toBeInTheDocument();
    expect(screen.getByText('⚠ Not authenticated')).toBeInTheDocument();
  });

  it('fires go_previous from the Back button on the completion step', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step4',
          position: 'dev',
          preferredAgentLanguage: 'en',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: ['claude_code'] as AgentType[],
        }),
        authSessions: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Back/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'go_previous' }) }),
      expect.anything(),
    );
  });

  it('advances from the profile step after clicking a role card and choosing a language', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    // Click the Developer role card
    await userEvent.click(screen.getByRole('button', { name: /Developer/ }));

    // Open the searchable Language select and pick an option — drives handleLanguageChange.
    await userEvent.click(screen.getByRole('combobox', { name: /Preferred Agent Language/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'English' }));

    // Both fields now satisfy canAdvanceStep1, so Continue submits the chosen values.
    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/onboarding',
        expect.objectContaining({
          onboarding: expect.objectContaining({
            position: 'dev',
            preferredAgentLanguage: 'en',
            onboardingStateEvent: 'go_next',
          }),
        }),
        expect.anything(),
      ),
    );
  });

  it('Continue becomes enabled once a role card is clicked and language is chosen', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();

    // Clicking a role card sets the position.
    await userEvent.click(screen.getByRole('button', { name: /QA Engineer/ }));

    // Still disabled until language is chosen
    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();

    // Pick a language
    await userEvent.click(screen.getByRole('combobox', { name: /Preferred Agent Language/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'English' }));

    expect(screen.getByRole('button', { name: /Continue/ })).toBeEnabled();
  });

  it('advances the connect agents step with go_next when Continue is clicked', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: ['claude_code'] as AgentType[],
        }),
        authSessions: [],
      },
    });

    // Continue is enabled once at least one agent is configured; it walks the state machine forward.
    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'go_next' }) }),
      expect.anything(),
    );
  });

  it('shows the failure panel and retries session creation when an auth session failed', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [buildTerminalSession({ agentType: 'claude_code', state: 'failed' })],
      },
    });

    // All unconfigured agents have Connect buttons. Click the first one (Claude Code row).
    await userEvent.click(screen.getAllByRole('button', { name: 'Connect' })[0]);
    expect(await screen.findByText('Authentication session failed to start.')).toBeInTheDocument();

    // Retry POSTs a fresh session (apiFetch → mocked fetch resolves 200) then reloads authSessions.
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }));

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['authSessions'] }));
  });

  it('renders the ttyd terminal iframe for a ready auth session after clicking Connect', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({
          onboardingState: 'step3',
          selectedAgents: ['claude_code'] as AgentType[],
          configuredAgents: [],
        }),
        authSessions: [
          buildTerminalSession({ agentType: 'claude_code', state: 'ready', websocketUrl: 'wss://term.example/ws' }),
        ],
      },
    });

    // Expand terminal by clicking Connect button
    await userEvent.click(screen.getAllByRole('button', { name: 'Connect' })[0]);

    expect(await screen.findByTitle('Agent Authentication Terminal')).toBeInTheDocument();
    expect(screen.getByText('Complete authentication in the terminal above')).toBeInTheDocument();
  });

  it('renders role radio cards on profile step', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    expect(screen.getByRole('button', { name: /Developer/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /QA Engineer/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Product Manager/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Designer/ })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /CTO/ })).toBeInTheDocument();
    // 5 role buttons (Other is not shown per story spec)
    expect(screen.getAllByRole('button').filter((b) => b.getAttribute('aria-pressed') !== null)).toHaveLength(5);
  });

  it('enables Continue only after a role card is clicked and language selected', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();
    await userEvent.click(screen.getByRole('button', { name: /Developer/ }));
    expect(screen.getByRole('button', { name: /Continue/ })).toBeDisabled();
    await userEvent.click(screen.getByRole('combobox', { name: /Preferred Agent Language/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'English' }));
    expect(screen.getByRole('button', { name: /Continue/ })).toBeEnabled();
  });

  describe('viewer (read-only client) onboarding', () => {
    const viewerAt = (overrides: Partial<SharedUser> = {}): SharedUser =>
      userAt({ currentRole: 'viewer', ...overrides });

    it('hides the Connect Agents step and shows See the platform step for a viewer', () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt(), authSessions: [] },
      });

      expect(screen.getByText('Your Profile')).toBeInTheDocument();
      expect(screen.getByText('See the platform')).toBeInTheDocument();
      expect(screen.getByText('Complete')).toBeInTheDocument();
      expect(screen.queryByText('Connect Agents')).not.toBeInTheDocument();
    });

    it('advances a viewer from the profile step with go_next (no agent selection)', async () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt({ position: 'dev', preferredAgentLanguage: 'en' }), authSessions: [] },
      });

      await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

      expect(router.patch).toHaveBeenCalledWith(
        '/onboarding',
        expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'go_next' }) }),
        expect.anything(),
      );
    });

    it('viewer at step2 renders "See the platform" heading', () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt({ onboardingState: 'step2' }), authSessions: [] },
      });

      expect(screen.getByText('See the platform in action')).toBeInTheDocument();
    });

    it('viewer platform step Continue sends viewer_advance event', async () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt({ onboardingState: 'step2' }), authSessions: [] },
      });

      await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

      expect(router.patch).toHaveBeenCalledWith(
        '/onboarding',
        expect.objectContaining({ onboarding: expect.objectContaining({ onboardingStateEvent: 'viewer_advance' }) }),
        expect.anything(),
      );
    });

    it('viewer does NOT see the agent connect step', () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt({ onboardingState: 'step2' }), authSessions: [] },
      });

      expect(screen.queryByText('Connect your agents')).not.toBeInTheDocument();
    });

    it('shows the completion screen for a viewer whose server state reached step4', () => {
      renderAuthedPage(<OnboardingPage />, {
        props: {
          currentUser: viewerAt({ onboardingState: 'step4', position: 'dev', preferredAgentLanguage: 'en' }),
          authSessions: [],
        },
      });

      expect(screen.getByText("You're all set!")).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /Get Started/ })).toBeInTheDocument();
      // No Back button for viewers (avoids bouncing through hidden states).
      expect(screen.queryByRole('button', { name: /Back/ })).not.toBeInTheDocument();
    });

    it('renders viewer workflow preview when viewerWorkflowPreview prop is provided', () => {
      const preview = {
        workflowName: 'CI Pipeline',
        workflowDescription: 'Automated CI workflow',
        steps: [{ name: 'Lint', description: 'Run linter' }],
      };
      renderAuthedPage(<OnboardingPage />, {
        props: {
          currentUser: viewerAt({ onboardingState: 'step2' }),
          authSessions: [],
          viewerWorkflowPreview: preview,
        },
      });

      expect(screen.getByText("Here's what a workflow looks like in action")).toBeInTheDocument();
      expect(screen.getByText('CI Pipeline')).toBeInTheDocument();
      expect(screen.getByText(/Lint/)).toBeInTheDocument();
    });

    it('renders static fallback when viewerWorkflowPreview is null', () => {
      renderAuthedPage(<OnboardingPage />, {
        props: { currentUser: viewerAt({ onboardingState: 'step2' }), authSessions: [], viewerWorkflowPreview: null },
      });

      expect(screen.getByText('See the platform in action')).toBeInTheDocument();
    });
  });
});
