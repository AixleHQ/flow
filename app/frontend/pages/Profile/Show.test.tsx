import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { companyMembershipPath } from 'shared/routes';
import type { AgentCredential, SharedUser } from 'shared/ui';

import ProfilePage from './Show';

const acmeCompany = {
  id: 9,
  name: 'Acme Robotics',
  emailDomain: 'acme.test',
  logoUrl: null,
  primaryColor: null,
  secondaryColor: null,
};

const buildProfile = (overrides: Partial<SharedUser> = {}): SharedUser => ({
  id: 42,
  email: 'maria@acme.test',
  name: 'Maria Sokolova',
  state: 'active',
  position: null,
  preferredAgentLanguage: 'en',
  selectedAgents: [],
  onboardingState: 'completed',
  onboardingCompletedAt: '2026-01-01T00:00:00Z',
  defaultAgentCredentialId: null,
  defaultAgentRuntime: null,
  configuredAgents: [],
  needsAgentSetup: false,
  agentCredentials: [],
  shareActiveSessions: false,
  shareCompletedSessions: true,
  currentRole: 'admin',
  currentCompany: acmeCompany,
  memberships: [{ id: 5, role: 'admin', state: 'active', company: acmeCompany }],
  ...overrides,
});

const buildCredential = (overrides: Partial<AgentCredential> = {}): AgentCredential => ({
  id: 100,
  agentType: 'claude_code',
  configKeys: [],
  defaultModel: null,
  lastUsedAt: null,
  expiresAt: null,
  connectionStatus: 'active',
  createdAt: '2026-01-02T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  ...overrides,
});

const baseProps = (profile: SharedUser) => ({
  profile,
  languageOptions: ['en', 'es'],
  mcp: { enabled: false, lastUsedAt: null, serverUrl: 'http://localhost:4000/mcp', token: null },
  agentModels: [],
});

// A pinned useForm() stub leaks to EVERY useForm() in the tree, including the sidebar's
// CreateProjectModal which reads data.name/data.description. So seed a superset shape that
// satisfies both ProfilePage (data.profile.*) and CreateProjectModal (data.name/description).
const pinForm = (name: string, preferredAgentLanguage = 'en') => {
  const form = makeFormStub({
    profile: { name, preferredAgentLanguage, shareActiveSessions: false, shareCompletedSessions: true },
    name: '',
    description: '',
  });
  form.isDirty = true;
  return form;
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Profile/Show', () => {
  it('renders the profile heading, email and company name from seeded props', () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('heading', { name: 'My Profile' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Personal Information' })).toBeInTheDocument();
    expect(screen.getByText('maria@acme.test')).toBeInTheDocument();
    // The company name appears twice on purpose: the scope banner under the
    // title ("Settings for Acme Robotics") and the Companies card. Both matter —
    // the banner is what stops the page reading as one shared set of agents.
    expect(screen.getAllByText('Acme Robotics').length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText(/Your agents and agent language are set per company/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save Changes' })).toBeInTheDocument();
  });

  it('shows the no-credentials empty state for the default agent runtime when none are configured', () => {
    const profile = buildProfile({ agentCredentials: [], configuredAgents: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(
      screen.getByText('No agent credentials configured. Complete onboarding to set up agents.'),
    ).toBeInTheDocument();
    // Each available agent renders an Authenticate CTA when not yet connected.
    expect(screen.getAllByRole('button', { name: 'Authenticate' }).length).toBeGreaterThan(0);
  });

  it('disables Save and never submits when the display name is too short to be valid', async () => {
    const form = pinForm('a'); // length 1 -> isFormValid is false
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    const save = screen.getByRole('button', { name: 'Save Changes' });
    expect(save).toBeDisabled();

    await userEvent.click(save);
    expect(form.patch).not.toHaveBeenCalled();
  });

  it('submits the profile form to /profile when the data is valid and dirty', async () => {
    const form = pinForm('Maria Sokolova');
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    expect(form.patch).toHaveBeenCalledWith('/profile', expect.objectContaining({ preserveScroll: true }));
  });

  it('removes a credential via router.delete after the user confirms the prompt', async () => {
    const credential = buildCredential({ id: 777, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    // The connected agent card shows a Connected badge, a Re-authenticate button, and an
    // icon-only remove button. Locate the card via its unique Re-authenticate action.
    expect(screen.getByText('Connected')).toBeInTheDocument();
    const reauth = screen.getByRole('button', { name: 'Re-authenticate' });
    const card = reauth.closest('.mantine-Card-root') as HTMLElement;
    const buttons = within(card).getAllByRole('button');
    // The remove-credentials icon button is the last action in the card.
    await userEvent.click(buttons[buttons.length - 1]);

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith(
        '/profile/destroy_credential',
        expect.objectContaining({ data: { agentCredentialId: 777 } }),
      ),
    );
  });

  it('offers a Connect Design button for a Claude credential with a claude.ai OAuth token', () => {
    const credential = buildCredential({ agentType: 'claude_code', configKeys: ['claudeAiOauth'] });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('button', { name: 'Connect Design' })).toBeInTheDocument();
  });

  it('labels the design button "Reconnect Design" once a designOauth block exists', () => {
    const credential = buildCredential({ agentType: 'claude_code', configKeys: ['claudeAiOauth', 'designOauth'] });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('button', { name: 'Reconnect Design' })).toBeInTheDocument();
  });

  it('offers Connect Design for a Console (managed-key) Claude credential too', () => {
    // /design-login layers on either base — claude.ai OR the platform.claude.com key.
    const credential = buildCredential({ agentType: 'claude_code', configKeys: ['primaryApiKey'] });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('button', { name: 'Connect Design' })).toBeInTheDocument();
  });

  it('hides the design button for a Claude credential with no base login at all', () => {
    const credential = buildCredential({ agentType: 'claude_code', configKeys: [] });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.queryByRole('button', { name: /Design/ })).not.toBeInTheDocument();
  });

  it('shows an "Expiring soon" badge for an agent credential nearing token expiry', () => {
    const credential = buildCredential({ agentType: 'claude_code', connectionStatus: 'expiring' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Expiring soon')).toBeInTheDocument();
    expect(screen.queryByText('Connected')).not.toBeInTheDocument();
  });

  it('does NOT remove a credential when the user cancels the confirm prompt', async () => {
    const credential = buildCredential({ id: 888, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    const reauth = screen.getByRole('button', { name: 'Re-authenticate' });
    const card = reauth.closest('.mantine-Card-root') as HTMLElement;
    const buttons = within(card).getAllByRole('button');
    await userEvent.click(buttons[buttons.length - 1]);

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    expect(router.delete).not.toHaveBeenCalled();
  });

  it('shows the Platform Administrator label for a super_admin with no memberships', () => {
    const profile = buildProfile({ currentRole: 'super_admin', currentCompany: null, memberships: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Platform Administrator')).toBeInTheDocument();
  });

  it('shows a monogram tile with the company initials on a membership row', () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('AR')).toBeInTheDocument();
  });

  it('leaves a company via the shared confirm modal after the user confirms', async () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await userEvent.click(screen.getByRole('button', { name: 'Leave Acme Robotics' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/Are you sure you want to leave Acme Robotics/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Leave company' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith(
        companyMembershipPath(5),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('does NOT leave a company when the confirm modal is cancelled', async () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await userEvent.click(screen.getByRole('button', { name: 'Leave Acme Robotics' }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    expect(router.delete).not.toHaveBeenCalled();
  });

  it('renders the Employee role badge on an employee membership row', () => {
    const profile = buildProfile({
      currentRole: 'employee',
      memberships: [{ id: 5, role: 'employee', state: 'active', company: acmeCompany }],
    });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Employee')).toBeInTheDocument();
  });

  it('shows the no-memberships empty state when the profile belongs to no company', () => {
    const profile = buildProfile({ currentRole: 'employee', currentCompany: null, memberships: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('No company memberships')).toBeInTheDocument();
  });

  it('lists all five available agent runtimes with their names and descriptions', () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();
    expect(screen.getByText('OpenAI Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();
    expect(screen.getByText('Grok')).toBeInTheDocument();
    expect(screen.getByText("Anthropic's AI coding assistant with deep reasoning capabilities")).toBeInTheDocument();
  });

  it('shows the Default Runtime selector and Default Models rows when credentials exist', () => {
    const credential = buildCredential({ id: 100, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    // The Agent Defaults card holds both the runtime selector and the model rows.
    expect(screen.getByRole('heading', { name: 'Agent Defaults' })).toBeInTheDocument();
    expect(screen.getByText('Default Runtime')).toBeInTheDocument();
    expect(
      screen.queryByText('No agent credentials configured. Complete onboarding to set up agents.'),
    ).not.toBeInTheDocument();

    // Default Models renders with one labelled row per credential.
    expect(screen.getByText('Default Models')).toBeInTheDocument();
    // The per-credential model row shows the agent's display name (in addition to the runtime card).
    expect(screen.getAllByText('Claude Code').length).toBeGreaterThan(1);
  });

  it('hides the Default Models card when there are no credentials', () => {
    const profile = buildProfile({ agentCredentials: [], configuredAgents: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.queryByText('Default Models')).not.toBeInTheDocument();
  });

  it('shows configured/last-used metadata for a connected credential', () => {
    const credential = buildCredential({
      id: 200,
      agentType: 'cursor_cli',
      createdAt: '2026-01-02T00:00:00Z',
      lastUsedAt: '2026-02-10T00:00:00Z',
    });
    const profile = buildProfile({ configuredAgents: ['cursor_cli'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Connected')).toBeInTheDocument();
    // formatDate renders "Configured <date> · Last used <date>" inside one Text node.
    expect(screen.getByText(/Configured/)).toHaveTextContent(/Last used/);
  });

  it('renders Authenticate (not Re-authenticate) for an agent that has no credential', () => {
    // Only claude_code is configured; the other four should show Authenticate.
    const credential = buildCredential({ id: 300, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('button', { name: 'Re-authenticate' })).toBeInTheDocument();
    // The four unconfigured agents each render an Authenticate button.
    expect(screen.getAllByRole('button', { name: 'Authenticate' })).toHaveLength(4);
  });

  it('shows the session visibility switches in the state the profile reports', () => {
    const profile = buildProfile({ shareActiveSessions: true, shareCompletedSessions: false });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('switch', { name: /Show my active sessions/ })).toBeChecked();
    expect(screen.getByRole('switch', { name: /Show my finished sessions/ })).not.toBeChecked();
  });

  it('records a flipped visibility switch on the form', async () => {
    const profile = buildProfile();
    const form = pinForm('Maria Sokolova');
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    await userEvent.click(screen.getByRole('switch', { name: /Show my active sessions/ }));

    expect(form.setData).toHaveBeenCalledWith('profile', expect.objectContaining({ shareActiveSessions: true }));
  });

  it('keeps Save disabled when the form is not dirty even though data is valid', () => {
    // pinForm sets isDirty=true; here we want a clean (non-dirty) but valid form.
    const form = makeFormStub({
      profile: {
        name: 'Maria Sokolova',
        preferredAgentLanguage: 'en',
        shareActiveSessions: false,
        shareCompletedSessions: true,
      },
      name: '',
      description: '',
    });
    form.isDirty = false;
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    expect(screen.getByRole('button', { name: 'Save Changes' })).toBeDisabled();
  });

  it('renders Account and Usage tabs and navigates to the usage page when Usage is clicked', async () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('tab', { name: 'Account' })).toBeInTheDocument();
    const usageTab = screen.getByRole('tab', { name: 'Usage' });
    expect(usageTab).toBeInTheDocument();

    await userEvent.click(usageTab);
    expect(router.visit).toHaveBeenCalledWith('/profile/usage');
  });

  it('surfaces a server-side validation error on the display name field', () => {
    const form = pinForm('Maria Sokolova');
    form.errors = { 'profile.name': 'has already been taken' };
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    expect(screen.getByText('has already been taken')).toBeInTheDocument();
  });

  it('shows a client-side length error and does NOT submit when the display name exceeds 100 chars', async () => {
    // isFormValid only checks length >= 2, so the button is enabled for a too-long name; the zod
    // schema (max 100) then rejects it on submit, populating clientErrors and skipping the patch.
    const longName = 'a'.repeat(101);
    const form = pinForm(longName);
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile), form });

    const save = screen.getByRole('button', { name: 'Save Changes' });
    expect(save).toBeEnabled();

    await userEvent.click(save);

    expect(screen.getByText('Name must be less than 100 characters')).toBeInTheDocument();
    expect(form.patch).not.toHaveBeenCalled();
  });

  it('enables MCP by posting to the regenerate-token route when MCP is disabled', async () => {
    const profile = buildProfile();
    const props = {
      ...baseProps(profile),
      mcp: { enabled: false, lastUsedAt: null, serverUrl: 'http://localhost:4000/mcp', token: null },
    };
    renderAuthedPage(<ProfilePage {...props} />, { props });

    // Disabled state: primary CTA reads "Enable MCP" and there is no Disable action yet.
    expect(screen.queryByRole('button', { name: 'Disable' })).not.toBeInTheDocument();
    expect(screen.queryByText(/MCP access is enabled/)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Enable MCP' }));

    expect(router.post).toHaveBeenCalledWith(
      '/profile/regenerate_mcp_token',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('regenerates and disables the MCP token via the router when MCP is enabled', async () => {
    const profile = buildProfile();
    const props = {
      ...baseProps(profile),
      mcp: { enabled: true, lastUsedAt: '2026-03-01T12:00:00Z', serverUrl: 'http://localhost:4000/mcp', token: null },
    };
    renderAuthedPage(<ProfilePage {...props} />, { props });

    // Enabled-without-token hint includes the last-used timestamp.
    expect(screen.getByText(/MCP access is enabled/)).toHaveTextContent(/Last used/);

    await userEvent.click(screen.getByRole('button', { name: 'Regenerate token' }));
    expect(router.post).toHaveBeenCalledWith(
      '/profile/regenerate_mcp_token',
      {},
      expect.objectContaining({ preserveScroll: true }),
    );

    await userEvent.click(screen.getByRole('button', { name: 'Disable' }));
    expect(router.delete).toHaveBeenCalledWith(
      '/profile/disable_mcp_token',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows the not-used-yet hint when MCP is enabled but has never been used', () => {
    const profile = buildProfile();
    const props = {
      ...baseProps(profile),
      mcp: { enabled: true, lastUsedAt: null, serverUrl: 'http://localhost:4000/mcp', token: null },
    };
    renderAuthedPage(<ProfilePage {...props} />, { props });

    expect(screen.getByText(/MCP access is enabled/)).toHaveTextContent(/Not used yet/);
  });

  it('renders the one-time MCP token and the ready-to-paste Claude command when a token is present', () => {
    const profile = buildProfile();
    const props = {
      ...baseProps(profile),
      mcp: { enabled: true, lastUsedAt: null, serverUrl: 'http://localhost:4000/mcp', token: 'mcp_tok_abc123' },
    };
    renderAuthedPage(<ProfilePage {...props} />, { props });

    expect(screen.getByText('Your token — copy it now, it will not be shown again:')).toBeInTheDocument();
    // The token renders on its own in a Code block…
    expect(screen.getByText('mcp_tok_abc123')).toBeInTheDocument();
    // …and is embedded in the copyable `claude mcp add` command with the server URL.
    const command = screen.getByText(/claude mcp add aixle --transport http/);
    expect(command).toHaveTextContent('http://localhost:4000/mcp');
    expect(command).toHaveTextContent('Authorization: Bearer mcp_tok_abc123');
    // With MCP already enabled the primary button rotates the token rather than enabling.
    expect(screen.getByRole('button', { name: 'Regenerate token' })).toBeInTheDocument();
  });

  it('patches the default agent runtime when a different credential is selected', async () => {
    const claude = buildCredential({ id: 100, agentType: 'claude_code' });
    const cursor = buildCredential({ id: 200, agentType: 'cursor_cli' });
    const profile = buildProfile({
      configuredAgents: ['claude_code', 'cursor_cli'],
      agentCredentials: [claude, cursor],
      defaultAgentCredentialId: 100,
    });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    // Scope to the Default Runtime field (two+ credentials keep the Select enabled) and pick the other agent.
    const runtimeField = screen.getByText('Default Runtime').closest('div') as HTMLElement;
    const select = within(runtimeField).getByRole('combobox');
    await userEvent.click(select);
    await userEvent.click(await screen.findByRole('option', { name: 'Cursor CLI' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/profile',
      { profile: { defaultAgentCredentialId: 200 } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('puts the chosen default model for a credential when a model is selected', async () => {
    const credential = buildCredential({ id: 100, agentType: 'claude_code' }); // defaultModel null -> empty select
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    const props = {
      ...baseProps(profile),
      agentModels: [
        {
          agentType: 'claude_code',
          models: [
            { modelId: 'claude-sonnet-4-5', displayName: 'Claude Sonnet 4.5', description: 'Balanced' },
            { modelId: 'claude-opus-4', displayName: 'Claude Opus 4', description: 'Deep reasoning' },
          ],
        },
      ],
    };
    renderAuthedPage(<ProfilePage {...props} />, { props });

    // Default Models has one row (one credential) -> a single combobox to disambiguate,
    // scoped to the section following the "Default Models" label.
    const modelsSection = screen.getByText('Default Models').parentElement as HTMLElement;
    const select = within(modelsSection).getByRole('combobox');
    await userEvent.click(select);
    await userEvent.click(await screen.findByRole('option', { name: 'Claude Sonnet 4.5' }));

    expect(router.put).toHaveBeenCalledWith(
      '/profile/update_default_model',
      { agentCredentialId: 100, defaultModel: 'claude-sonnet-4-5' },
      expect.objectContaining({ preserveScroll: true, preserveState: true }),
    );
  });

  it('opens the authentication modal and starts a terminal session when Re-authenticate is clicked', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const credential = buildCredential({ id: 400, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await userEvent.click(screen.getByRole('button', { name: 'Re-authenticate' }));

    // Modal launches `claude` directly — the login method is chosen inside Claude's own TUI.
    expect(await screen.findByText('Authenticate Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Starting authentication session...')).toBeInTheDocument();
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith('/api/v1/terminal_sessions', expect.objectContaining({ method: 'POST' })),
    );
  });

  // == AWS Bedrock connection ==
  //
  // Claude Code hides Bedrock errors, so a broken connection otherwise presents as an
  // agent that never answers. The profile is where the user finds out why.

  const stubAwsFetch = (state: object, health?: object) =>
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = String(input);
      const json = (body: object) =>
        new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });

      if (url.includes('/cloud/aws_connection/health')) return json(health ?? {});
      if (url.includes('/cloud/aws_connection')) return json(state);
      return json({});
    });

  // There is deliberately no separate cloud entry point: the user declares that intent by
  // picking Amazon Bedrock inside Claude Code's own login wizard, and the auth modal offers
  // the connect step when the credential helper reports there is nothing to vend.
  it('offers no separate Connect AWS button', async () => {
    stubAwsFetch({ connected: false, reason: null });
    const profile = buildProfile({ configuredAgents: [], agentCredentials: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await waitFor(() => expect(screen.getAllByRole('button', { name: 'Authenticate' }).length).toBeGreaterThan(0));
    expect(screen.queryByRole('button', { name: /Connect AWS/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Reconnect AWS/i })).not.toBeInTheDocument();
  });

  // The one question the card has to answer is "will this actually run".
  it('states plainly that a healthy connection bills to the user AWS, and where', async () => {
    stubAwsFetch({
      connected: true,
      reason: null,
      account_id: '111122223333',
      role_name: 'BedrockUser',
      region: 'us-east-1',
    });
    const profile = buildProfile({ configuredAgents: [], agentCredentials: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(await screen.findByText('Billing to your AWS')).toBeInTheDocument();
    expect(screen.getByText(/111122223333 \/ BedrockUser · us-east-1/)).toBeInTheDocument();
  });

  it('says a rotten connection needs reconnecting, with the reason', async () => {
    stubAwsFetch({ connected: false, reason: 'registration_expired' });
    const profile = buildProfile({ configuredAgents: [], agentCredentials: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(await screen.findByText('AWS needs reconnecting')).toBeInTheDocument();
    expect(screen.getByText(/registration expired/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Test' })).toBeInTheDocument();
  });

  it('surfaces the provider message verbatim when the connection test fails', async () => {
    stubAwsFetch(
      { connected: true, reason: null },
      {
        ok: false,
        stage: 'invoke',
        error_code: 'AccessDeniedException',
        error_message: 'not authorized to perform bedrock:InvokeModel',
      },
    );
    const profile = buildProfile({ configuredAgents: [], agentCredentials: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await userEvent.click(await screen.findByRole('button', { name: 'Test' }));

    expect(await screen.findByText('not authorized to perform bedrock:InvokeModel')).toBeInTheDocument();
  });

  it('reports a reachable connection with the model it probed', async () => {
    stubAwsFetch({ connected: true, reason: null }, { ok: true, model_id: 'us.anthropic.claude-sonnet-4-6' });
    const profile = buildProfile({ configuredAgents: [], agentCredentials: [] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    await userEvent.click(await screen.findByRole('button', { name: 'Test' }));

    expect(await screen.findByText(/AWS Bedrock reachable/i)).toBeInTheDocument();
  });
});
