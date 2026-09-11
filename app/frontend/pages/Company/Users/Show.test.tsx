import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import UserShow, { type UserShowProps } from './Show';

type SessionFixture = UserShowProps['sessions'][number];

function makeSession(overrides: Partial<SessionFixture> = {}): SessionFixture {
  return {
    id: 101,
    sessionType: 'agent_session',
    agentType: 'claude_code',
    state: 'finished',
    mode: null,
    startedAt: '2026-06-26T10:00:00Z',
    finishedAt: '2026-06-26T10:05:00Z',
    createdAt: '2026-06-26T09:59:00Z',
    totalTokens: 12000,
    costCents: 250,
    userId: 7,
    userName: 'Jane Doe',
    userEmail: 'jane@example.com',
    projectId: 9,
    projectName: 'Analytics Revamp',
    artifactsReviewed: null,
    pendingArtifactsCount: 0,
    initialPrompt: 'Refactor the onboarding status chips',
    viewable: true,
    ...overrides,
  };
}

function seed(overrides: Partial<UserShowProps> = {}): UserShowProps {
  return {
    member: {
      id: 7,
      name: 'Jane Doe',
      email: 'jane@example.com',
      role: 'employee',
      state: 'active',
      position: 'dev',
      invitedAt: '2026-01-05T10:00:00Z',
      acceptedAt: '2026-01-06T10:00:00Z',
      createdAt: '2026-01-05T10:00:00Z',
    },
    viewerIsSelf: false,
    total: 1,
    sessions: [makeSession()],
    viewerIsAdmin: true,
    accessibleProjectIds: [9],
    usageLimits: [],
    period: '30d',
    ...overrides,
  };
}

// `<Deferred>` (test/setup.ts) renders its children only once the named prop is
// present on usePage() — so a deferred prop has to be seeded as a page prop as
// well as passed to the component.
function renderUser(props: UserShowProps, pageProps: Record<string, unknown> = {}) {
  return renderAuthedPage(<UserShow {...props} />, {
    props: { usageLimits: props.usageLimits, ...pageProps },
  });
}

const okLimits: UserShowProps['usageLimits'] = [
  {
    agentType: 'claude_code',
    status: 'ok',
    windows: [
      { key: 'five_hour', utilization: 100, resetsAt: '2026-06-26T15:00:00Z' },
      { key: 'seven_day', utilization: 100, resetsAt: '2026-06-29T00:00:00Z' },
    ],
    extraUsage: { enabled: true, utilization: 100, monthlyLimit: 50, usedCredits: 50 },
    fetchedAt: '2026-06-26T12:00:00Z',
  },
];

describe('Company/Users/Show', () => {
  it('renders the person: name, email, role and membership state', () => {
    renderUser(seed());

    expect(screen.getByRole('heading', { name: 'Jane Doe' })).toBeInTheDocument();
    expect(screen.getByText('jane@example.com')).toBeInTheDocument();
    expect(screen.getByText('Employee')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
  });

  it('marks the viewer when they open their own profile', () => {
    const { rerender } = renderUser(seed());
    expect(screen.queryByText('You')).not.toBeInTheDocument();

    rerender(<UserShow {...seed({ viewerIsSelf: true })} />);
    expect(screen.getByText('You')).toBeInTheDocument();
  });

  it('shows the exhausted plan: 100% used, 0% remaining and the reset time', () => {
    renderUser(seed({ usageLimits: okLimits }));

    expect(screen.getByText('Usage limits')).toBeInTheDocument();
    expect(screen.getAllByText('100% used · 0% remaining').length).toBe(2);
    expect(screen.getByText('50 / 50 credits')).toBeInTheDocument();
  });

  it('puts a re-auth failure in the third person and offers the viewer no action', () => {
    renderUser(
      seed({
        usageLimits: [
          { agentType: 'claude_code', status: 'unauthorized', windows: [], fetchedAt: '2026-06-26T12:00:00Z' },
        ],
      }),
    );

    expect(
      screen.getByText(
        "Jane Doe's Claude Code sign-in no longer works — only they can reconnect it, from their own profile.",
      ),
    ).toBeInTheDocument();
  });

  it('hides the card entirely when no credential bills against a plan', () => {
    renderUser(seed({ usageLimits: [] }));

    expect(screen.queryByText('Usage limits')).not.toBeInTheDocument();
  });

  it('renders the session list without a User column — the page is already about one person', () => {
    renderUser(seed());

    const table = screen.getByRole('table');
    expect(within(table).getByText('Refactor the onboarding status chips')).toBeInTheDocument();
    expect(within(table).getByText('Analytics Revamp')).toBeInTheDocument();
    expect(within(table).queryByText('User')).not.toBeInTheDocument();
    expect(screen.getByText('1 entry')).toBeInTheDocument();
  });

  it('opens rows through the company page for an admin', () => {
    renderUser(seed({ viewerIsAdmin: true }));

    expect(screen.getByRole('link', { name: 'Open session #101' })).toHaveAttribute('href', '/company/sessions/101');
  });

  it('opens rows through the project page for a non-admin who is on that project', () => {
    renderUser(seed({ viewerIsAdmin: false, accessibleProjectIds: [9] }));

    expect(screen.getByRole('link', { name: 'Open session #101' })).toHaveAttribute(
      'href',
      '/company/projects/9/sessions/101',
    );
  });

  it('keeps a row the viewer has no route to, but not as a link', () => {
    renderUser(seed({ viewerIsAdmin: false, accessibleProjectIds: [] }));

    expect(screen.queryByRole('link', { name: 'Open session #101' })).not.toBeInTheDocument();
    expect(within(screen.getByRole('table')).getByText('$2.50')).toBeInTheDocument();
  });

  it('locks a private session: no open link, a lock icon, cost still shown', () => {
    renderUser(seed({ sessions: [makeSession({ viewable: false, initialPrompt: null })] }));

    expect(screen.queryByRole('link', { name: 'Open session #101' })).not.toBeInTheDocument();
    expect(screen.getByLabelText('Session #101 is private')).toBeInTheDocument();
    expect(within(screen.getByRole('table')).getByText('$2.50')).toBeInTheDocument();
  });

  it('has no account controls — this page is a read', () => {
    renderUser(seed({ usageLimits: okLimits }));

    expect(screen.queryByRole('button', { name: /leave company/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /connect/i })).not.toBeInTheDocument();
    expect(screen.queryByText(/mcp/i)).not.toBeInTheDocument();
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
  });

  it('offers the spend charts for a window the viewer can change', async () => {
    const user = userEvent.setup();
    renderUser(seed());

    expect(screen.getByRole('heading', { name: 'Usage' })).toBeInTheDocument();

    await user.click(screen.getByDisplayValue('Last 30 days'));
    await user.click(await screen.findByText('Last 7 days'));

    expect(router.get).toHaveBeenCalledWith('/user/7', { period: '7d' }, expect.anything());
  });

  it('renders the spend numbers once the deferred usage props arrive', () => {
    renderUser(seed(), {
      summary: {
        totalSessions: 1234,
        totalCostCents: 56789,
        totalTokens: 2_500_000,
        avgCostCentsPerSession: 46,
        workflowsRun: 42,
        projectBreakdowns: [
          { projectId: 11, projectName: 'Quasar Initiative', sessions: 800, costCents: 40000, tokens: 1_800_000 },
        ],
      },
    });

    expect(screen.getByText('Total Sessions')).toBeInTheDocument();
    expect(screen.getByText('1,234')).toBeInTheDocument();
    expect(screen.getByText('Per-Project Breakdown')).toBeInTheDocument();
    expect(screen.getByText('Quasar Initiative')).toBeInTheDocument();
  });

  it('says so plainly when the person has run nothing here', () => {
    renderUser(seed({ sessions: [], total: 0 }));

    expect(screen.getByText("Jane Doe hasn't run anything in this company yet")).toBeInTheDocument();
  });
});
