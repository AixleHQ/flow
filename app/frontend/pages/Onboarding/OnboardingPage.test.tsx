import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import type { AgentType, SharedUser } from 'shared/ui';
import type TerminalSession from 'types/generated/TerminalSession';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';
import { buildSharedUser } from 'test/factories/sharedProps';

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
  sessionConfig: null,
  toolIds: [],
  skillIds: [],
  mcpServerIds: [],
  inputAssetIds: [],
  repositoryIds: [],
  pendingArtifactsCount: 0,
  sessionLogsCount: 0,
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
    expect(screen.getByText("Let's set up your profile and AI agents to get started")).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Continue/ })).toBeInTheDocument();
  });

  it('blocks advancing from the profile step when required fields are empty', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ position: null, preferredAgentLanguage: '' }), authSessions: [] },
    });

    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(screen.getByText(/Please fill in all required fields to continue/)).toBeInTheDocument();
    expect(router.patch).not.toHaveBeenCalled();
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

  it('renders the agent selection step and toggling an agent auto-saves to the backend', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ onboardingState: 'step2' }), authSessions: [] },
    });

    expect(screen.getByText('Select your AI agents')).toBeInTheDocument();
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();

    await userEvent.click(screen.getByText('Claude Code'));

    // autoSave is debounced (~300ms) before it calls router.patch.
    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/onboarding',
        expect.objectContaining({
          onboarding: expect.objectContaining({ selectedAgents: ['claude_code'] as AgentType[] }),
        }),
        expect.anything(),
      ),
    );
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

  it('renders the welcome card with the company name and the four stepper labels', () => {
    renderAuthedPage(<OnboardingPage />, { props: { currentUser: userAt(), authSessions: [] } });

    // SharedProps default seeds company 'Test Company'.
    expect(screen.getByText('Welcome to Test Company!')).toBeInTheDocument();
    expect(screen.getByText('Your Profile')).toBeInTheDocument();
    expect(screen.getByText('Select Agents')).toBeInTheDocument();
    expect(screen.getByText('Authenticate')).toBeInTheDocument();
    expect(screen.getByText('Complete')).toBeInTheDocument();
  });

  it('renders all four agent cards with their descriptions on the agent selection step', () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ onboardingState: 'step2' }), authSessions: [] },
    });

    expect(screen.getByText('OpenAI Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();
    expect(screen.getByText("Anthropic's AI coding assistant with deep reasoning capabilities")).toBeInTheDocument();
    expect(screen.getByText('Choose at least one agent to work with. You can change this later.')).toBeInTheDocument();
  });

  it('blocks advancing from the agent step when no agent is selected', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: { currentUser: userAt({ onboardingState: 'step2', selectedAgents: [] }), authSessions: [] },
    });

    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(screen.getByText(/Select at least one agent to continue/)).toBeInTheDocument();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('advances the agent step to the backend with go_next when an agent is pre-selected', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ onboardingState: 'step2', selectedAgents: ['codex'] as AgentType[] }),
        authSessions: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Continue/ }));

    expect(router.patch).toHaveBeenCalledWith(
      '/onboarding',
      expect.objectContaining({
        onboarding: expect.objectContaining({
          selectedAgents: ['codex'] as AgentType[],
          onboardingStateEvent: 'go_next',
        }),
      }),
      expect.anything(),
    );
  });

  it('fires go_previous when the Back button is clicked on the agent step', async () => {
    renderAuthedPage(<OnboardingPage />, {
      props: {
        currentUser: userAt({ onboardingState: 'step2', selectedAgents: ['claude_code'] as AgentType[] }),
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

  it('renders the authenticate step sidebar and the placeholder until an agent is picked', () => {
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

    expect(screen.getByText('Authenticate Your Agents')).toBeInTheDocument();
    expect(screen.getByText('Select an agent to authenticate')).toBeInTheDocument();
    // No agent configured yet → summary text shows the "none" branch.
    expect(screen.getByText('No agents authenticated yet.')).toBeInTheDocument();
    // Unconfigured agents with no active session show the "Click to authenticate" badge.
    expect(screen.getAllByText('Click to authenticate')).toHaveLength(2);
  });

  it('shows the authenticated badge, configured count, and an enabled Continue when an agent is configured', () => {
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

    expect(screen.getByText('Authenticated')).toBeInTheDocument();
    expect(screen.getByText('1 of 2 authenticated.')).toBeInTheDocument();

    const continueBtn = screen.getByRole('button', { name: /Continue \(1\/2\)/ });
    expect(continueBtn).toBeEnabled();
  });

  it('disables Continue on the authenticate step when no agent is configured', () => {
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

    expect(screen.getByRole('button', { name: /Continue \(0\/1\)/ })).toBeDisabled();
  });

  it('shows the "in progress" badge when an agent has an active auth session but is not configured', () => {
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

    expect(screen.getByText('In progress')).toBeInTheDocument();
  });

  it('clicking a configured agent in the sidebar reveals the "Authentication complete" panel', async () => {
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

    // The sidebar tile for the configured agent (its name appears once in the sidebar).
    await userEvent.click(screen.getByText('Claude Code'));

    expect(await screen.findByText('Authentication complete')).toBeInTheDocument();
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
});
