import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { UsageLimitsCard, formatResetsIn, type UsageLimitsEntry } from './UsageLimitsCard';

const buildEntry = (overrides: Partial<UsageLimitsEntry> = {}): UsageLimitsEntry => ({
  agentType: 'claude_code',
  status: 'ok',
  windows: [
    { key: 'five_hour', utilization: 33, resetsAt: '2026-08-16T18:00:00Z' },
    { key: 'seven_day', utilization: 13, resetsAt: '2026-08-20T00:59:59Z' },
  ],
  extraUsage: null,
  fetchedAt: '2026-08-16T12:00:00Z',
  ...overrides,
});

describe('UsageLimitsCard', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders nothing when no credential bills against a plan', () => {
    renderPage(<UsageLimitsCard entries={[]} />);

    expect(screen.queryByText('Usage limits')).not.toBeInTheDocument();
  });

  it('labels each window the way Claude Code does and shows how much is used', () => {
    renderPage(<UsageLimitsCard entries={[buildEntry()]} />);

    expect(screen.getByText('Current session (5 hours)')).toBeInTheDocument();
    expect(screen.getByText('Current week (all models)')).toBeInTheDocument();
    expect(screen.getByText('33% used · 67% remaining')).toBeInTheDocument();
    expect(screen.getByText('13% used · 87% remaining')).toBeInTheDocument();
  });

  it('shows model-scoped weeklies and extra usage when the account has them', () => {
    const entry = buildEntry({
      windows: [{ key: 'seven_day_opus', utilization: 91, resetsAt: null }],
      extraUsage: { enabled: true, utilization: 25, monthlyLimit: 100, usedCredits: 25 },
    });

    renderPage(<UsageLimitsCard entries={[entry]} />);

    expect(screen.getByText('Current week (Opus)')).toBeInTheDocument();
    expect(screen.getByText('91% used · 9% remaining')).toBeInTheDocument();
    expect(screen.getByText('Extra usage this month')).toBeInTheDocument();
    expect(screen.getByText('25 / 100 credits')).toBeInTheDocument();
  });

  it('tells the user to re-authenticate when the sign-in no longer works', () => {
    renderPage(<UsageLimitsCard entries={[buildEntry({ status: 'unauthorized', windows: [] })]} />);

    expect(screen.getByText(/re-authenticate/i)).toBeInTheDocument();
    expect(screen.queryByText('Current session (5 hours)')).not.toBeInTheDocument();
  });

  it('says the vendor is throttling instead of showing an empty panel', () => {
    renderPage(<UsageLimitsCard entries={[buildEntry({ status: 'rate_limited', windows: [] })]} />);

    expect(screen.getByText(/throttling usage checks/i)).toBeInTheDocument();
  });

  it('reloads only the usage prop when refreshed, asking the server for fresh numbers', async () => {
    const reload = vi.spyOn(router, 'reload').mockImplementation(() => undefined);
    renderPage(<UsageLimitsCard entries={[buildEntry()]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }));

    expect(reload).toHaveBeenCalledWith(expect.objectContaining({ only: ['usage_limits'], data: { refresh: '1' } }));
  });

  it('names the agent only when more than one runtime reports limits', () => {
    const { rerender } = renderPage(<UsageLimitsCard entries={[buildEntry()]} />);
    expect(screen.queryByText('Claude Code')).not.toBeInTheDocument();

    rerender(<UsageLimitsCard entries={[buildEntry(), buildEntry({ agentType: 'codex' })]} />);
    expect(screen.getByText('Claude Code')).toBeInTheDocument();
    expect(screen.getByText('OpenAI Codex')).toBeInTheDocument();
  });

  it('renders Codex windows using the exact upstream period and reports remaining usage', () => {
    renderPage(
      <UsageLimitsCard
        entries={[
          buildEntry({
            agentType: 'codex',
            windows: [
              { key: 'codex_primary', utilization: 42, resetsAt: '2026-08-16T14:00:00Z', windowDurationMins: 300 },
              { key: 'codex_secondary', utilization: 5, resetsAt: '2026-08-23T12:00:00Z', windowDurationMins: 10080 },
            ],
          }),
        ]}
      />,
    );

    expect(screen.getByText('Usage window (5 hours)')).toBeInTheDocument();
    expect(screen.getByText('Usage window (1 week)')).toBeInTheDocument();
    expect(screen.getByText('42% used · 58% remaining')).toBeInTheDocument();
    expect(screen.getByText('5% used · 95% remaining')).toBeInTheDocument();
  });

  it('uses provider-specific authentication and error messages', () => {
    const { rerender } = renderPage(
      <UsageLimitsCard entries={[buildEntry({ agentType: 'codex', status: 'unauthorized', windows: [] })]} />,
    );
    expect(screen.getByText(/OpenAI Codex sign-in no longer works/i)).toBeInTheDocument();

    rerender(<UsageLimitsCard entries={[buildEntry({ agentType: 'codex', status: 'unavailable', windows: [] })]} />);
    expect(screen.getByText(/Couldn't reach OpenAI/i)).toBeInTheDocument();
  });
});

describe('formatResetsIn', () => {
  const now = Date.parse('2026-08-16T12:00:00Z');

  it('counts down in the largest units that still say something useful', () => {
    expect(formatResetsIn('2026-08-16T12:45:00Z', now)).toBe('resets in 45m');
    expect(formatResetsIn('2026-08-16T14:30:00Z', now)).toBe('resets in 2h 30m');
    expect(formatResetsIn('2026-08-19T16:00:00Z', now)).toBe('resets in 3d 4h');
  });

  it('handles a window with no reset time and one that has already lapsed', () => {
    expect(formatResetsIn(null, now)).toBeNull();
    expect(formatResetsIn('2026-08-16T11:00:00Z', now)).toBe('resets now');
  });
});
