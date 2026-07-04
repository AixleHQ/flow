import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { AgentCredential, SharedUser } from 'shared/ui';

import ProfilePage from './Show';

const buildProfile = (overrides: Partial<SharedUser> = {}): SharedUser => ({
  id: 42,
  email: 'maria@acme.test',
  name: 'Maria Sokolova',
  role: 'admin',
  state: 'active',
  position: null,
  preferredAgentLanguage: 'en',
  selectedAgents: [],
  onboardingState: 'completed',
  onboardingCompletedAt: '2026-01-01T00:00:00Z',
  defaultAgentCredentialId: null,
  defaultAgentRuntime: null,
  configuredAgents: [],
  agentCredentials: [],
  company: {
    id: 9,
    name: 'Acme Robotics',
    emailDomain: 'acme.test',
    logoUrl: null,
    primaryColor: null,
    secondaryColor: null,
  },
  ...overrides,
});

const buildCredential = (overrides: Partial<AgentCredential> = {}): AgentCredential => ({
  id: 100,
  agentType: 'claude_code',
  configKeys: [],
  defaultModel: null,
  lastUsedAt: null,
  expiresAt: null,
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
    profile: { name, preferredAgentLanguage },
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
    expect(screen.getByText('Acme Robotics')).toBeInTheDocument();
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

    vi.spyOn(window, 'confirm').mockReturnValue(true);

    // The connected agent card shows a Connected badge, a Re-authenticate button, and an
    // icon-only remove button. Locate the card via its unique Re-authenticate action.
    expect(screen.getByText('Connected')).toBeInTheDocument();
    const reauth = screen.getByRole('button', { name: 'Re-authenticate' });
    const card = reauth.closest('.mantine-Card-root') as HTMLElement;
    const buttons = within(card).getAllByRole('button');
    // The remove-credentials icon button is the last action in the card.
    await userEvent.click(buttons[buttons.length - 1]);

    expect(window.confirm).toHaveBeenCalled();
    expect(router.delete).toHaveBeenCalledWith(
      '/profile/destroy_credential',
      expect.objectContaining({ data: { agentCredentialId: 777 } }),
    );
  });

  it('does NOT remove a credential when the user cancels the confirm prompt', async () => {
    const credential = buildCredential({ id: 888, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    vi.spyOn(window, 'confirm').mockReturnValue(false);

    const reauth = screen.getByRole('button', { name: 'Re-authenticate' });
    const card = reauth.closest('.mantine-Card-root') as HTMLElement;
    const buttons = within(card).getAllByRole('button');
    await userEvent.click(buttons[buttons.length - 1]);

    expect(window.confirm).toHaveBeenCalled();
    expect(router.delete).not.toHaveBeenCalled();
  });

  it('renders the Super Admin role badge for a super_admin profile', () => {
    const profile = buildProfile({ role: 'super_admin' });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Super Admin')).toBeInTheDocument();
  });

  it('renders the Employee role badge for an employee profile', () => {
    const profile = buildProfile({ role: 'employee' });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Employee')).toBeInTheDocument();
  });

  it('falls back to the Platform Administrator label when the profile has no company', () => {
    const profile = buildProfile({ company: null });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Platform Administrator')).toBeInTheDocument();
  });

  it('lists all four available agent runtimes with their names and descriptions', () => {
    const profile = buildProfile();
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('Cursor CLI')).toBeInTheDocument();
    expect(screen.getByText('OpenAI Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini CLI')).toBeInTheDocument();
    expect(screen.getByText("Anthropic's AI coding assistant with deep reasoning capabilities")).toBeInTheDocument();
  });

  it('shows the Default Agent Runtime selector and Default Models card when credentials exist', () => {
    const credential = buildCredential({ id: 100, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    // Title appears for the runtime selector once credentials are present.
    expect(screen.getByText('Default Agent Runtime')).toBeInTheDocument();
    expect(
      screen.queryByText('No agent credentials configured. Complete onboarding to set up agents.'),
    ).not.toBeInTheDocument();

    // Default Models card renders with one labelled row per credential.
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
    // Only claude_code is configured; the other three should show Authenticate.
    const credential = buildCredential({ id: 300, agentType: 'claude_code' });
    const profile = buildProfile({ configuredAgents: ['claude_code'], agentCredentials: [credential] });
    renderAuthedPage(<ProfilePage {...baseProps(profile)} />, { props: baseProps(profile) });

    expect(screen.getByRole('button', { name: 'Re-authenticate' })).toBeInTheDocument();
    // The three unconfigured agents each render an Authenticate button.
    expect(screen.getAllByRole('button', { name: 'Authenticate' })).toHaveLength(3);
  });

  it('keeps Save disabled when the form is not dirty even though data is valid', () => {
    // pinForm sets isDirty=true; here we want a clean (non-dirty) but valid form.
    const form = makeFormStub({
      profile: { name: 'Maria Sokolova', preferredAgentLanguage: 'en' },
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
});
