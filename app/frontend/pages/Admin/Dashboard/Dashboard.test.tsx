import '@testing-library/jest-dom/vitest';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { buildUsageDay } from 'test/factories/adminDashboard';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { render, screen, userEvent, within } from 'test/renderPage';

import Dashboard from './Dashboard';
import type { DashboardData } from './types';

const now = new Date('2026-10-19T12:00:00Z');

const data: DashboardData = {
  tenants: [
    { id: 1, name: 'Acme' },
    { id: 2, name: 'Globex' },
  ],
  days: [
    buildUsageDay({ companyId: 1, day: '2026-09-15', sessionsSucceeded: 10 }),
    buildUsageDay({ companyId: 1, day: '2026-10-14', sessionsSucceeded: 20 }),
    buildUsageDay({
      companyId: 2,
      day: '2026-10-15',
      offeredSeconds: 0,
      unlimitedSeconds: 24 * 3600,
      limitMin: null,
      limitMax: null,
      billingClass: 'managed',
    }),
  ],
  measuredThrough: '2026-10-19T11:00:00Z',
  snapshot: { companies: 2, members: 14, projects: 5 },
};

const rowOf = (name: string) => screen.getByRole('row', { name: new RegExp(`^${name}`) });
const tile = (name: string) => within(screen.getByRole('region', { name }));

describe('Dashboard', () => {
  beforeEach(() => {
    answerFetch({ 'GET /admin/dashboard/waits.json': [] });
  });

  it('opens on the current month, one row per company, with why each is billed or not', () => {
    render(<Dashboard data={data} now={now} />);

    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('October 2026 (current)');
    expect(screen.getByText('Oct 14 – Oct 15, 2026 · to date · 2 companies')).toBeInTheDocument();
    expect(within(rowOf('Acme')).getByText('Paying')).toBeInTheDocument();
    expect(within(rowOf('Globex')).getByText('Free · managed')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Acme' })).toBeInTheDocument();
  });

  it('shows the platform as it stands in tiles', () => {
    render(<Dashboard data={data} now={now} />);

    expect(tile('Companies').getByText('2')).toBeInTheDocument();
    expect(tile('Companies').getByText('1 paying · 1 managed')).toBeInTheDocument();
    expect(tile('People').getByText('14')).toBeInTheDocument();
    expect(tile('Projects').getByText('5')).toBeInTheDocument();
  });

  it('shows what the period used in tiles, and how much of it nobody pays for', () => {
    render(<Dashboard data={data} now={now} />);

    expect(tile('Busy hours').getByText('96')).toBeInTheDocument();
    expect(tile('Busy hours').getByText('50% not on a paid plan')).toBeInTheDocument();
    expect(tile('Successful sessions').getByText('58')).toBeInTheDocument();
    expect(tile('Successful sessions').getByText('▲ +480%')).toBeInTheDocument();
  });

  it('flags a company that runs free without being managed', () => {
    const unbilled = {
      ...data,
      days: [...data.days, buildUsageDay({ companyId: 1, day: '2026-10-16', billingClass: 'unlimited' as const })],
    };
    render(<Dashboard data={unbilled} now={now} />);

    expect(within(rowOf('Acme')).getByText('Not billed · no limit')).toBeInTheDocument();
    expect(tile('Companies').getByText(/1 not billed/)).toBeInTheDocument();
  });

  it("shows each company's p95 wait for the period, and its change from the period before", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async (input) =>
        jsonResponse(
          String(input).includes('from=2026-10-01') ? [{ companyId: 1, p95: 600 }] : [{ companyId: 1, p95: 400 }],
        ),
      );
    render(<Dashboard data={data} now={now} />);

    expect(await within(rowOf('Acme')).findByText('10 min')).toBeInTheDocument();
    expect(await within(rowOf('Acme')).findByText('▲ +50%')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledWith(
      '/admin/dashboard/waits.json?from=2026-10-01&to=2026-10-31',
      expect.objectContaining({ headers: { Accept: 'application/json' } }),
    );
  });

  it('says so when the p95 wait cannot be loaded', async () => {
    answerFetch({ 'GET /admin/dashboard/waits.json': jsonResponse({ error: 'boom' }, 500) });
    render(<Dashboard data={data} now={now} />);

    expect(await screen.findByRole('alert')).toHaveTextContent('p95 wait could not be loaded');
  });

  it('shows a company without a limit as unlimited and fully used', () => {
    render(<Dashboard data={data} now={now} />);

    const globex = within(rowOf('Globex'));
    expect(globex.getAllByText('∞')).toHaveLength(2);
    const [, workerHours, busyHours, , , , utilization] = globex.getAllByRole('cell');
    expect(workerHours).toHaveTextContent(/^48/);
    expect(busyHours).toHaveTextContent(/^48/);
    expect(utilization).toHaveTextContent(/^100%/);
  });

  it('compares with the same days of the month before', () => {
    render(<Dashboard data={data} now={now} />);

    expect(screen.getByText('Change vs Sep 1 – Sep 15, 2026')).toBeInTheDocument();
    expect(within(rowOf('Acme')).getByText('▲ +100%')).toBeInTheDocument();
  });

  it('steps back to the previous month', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Previous period' }));

    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('September 2026');
    expect(screen.getByRole('rowheader', { name: 'Acme' })).toBeInTheDocument();
    expect(screen.queryByRole('rowheader', { name: 'Globex' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Previous period' })).toBeDisabled();
  });

  it('switches to a single day', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Day' }));

    expect(screen.getByRole('button', { name: 'Day' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('Thu, Oct 15, 2026');
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
  });

  it('sums a custom range', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Custom' }));

    expect(screen.getByLabelText('From')).toHaveValue('2026-10-01');
    expect(screen.getByLabelText('To')).toHaveValue('2026-10-19');
    expect(screen.getByText('Oct 1 – Oct 19, 2026 · custom range · 2 companies')).toBeInTheDocument();
  });

  it('filters companies by name', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search companies' }), 'glo');

    expect(screen.queryByRole('rowheader', { name: 'Acme' })).not.toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
  });

  it('sorts by a column, and reverses on a second click', async () => {
    render(<Dashboard data={data} now={now} />);
    const companiesInOrder = () => screen.getAllByRole('rowheader').map((cell) => cell.textContent);

    await userEvent.click(screen.getByRole('button', { name: 'Successful sessions' }));
    expect(companiesInOrder()).toEqual(['Globex', 'Acme', 'Total, all companies']);

    await userEvent.click(screen.getByRole('button', { name: 'Successful sessions' }));
    expect(companiesInOrder()).toEqual(['Acme', 'Globex', 'Total, all companies']);
    expect(screen.getByRole('columnheader', { name: /Successful sessions/ })).toHaveAttribute('aria-sort', 'ascending');
  });

  it('totals the period across companies', () => {
    render(<Dashboard data={data} now={now} />);

    expect(within(rowOf('Total, all companies')).getByText('58')).toBeInTheDocument();
  });

  it('shows the platform tiles and says so when no usage has been measured yet', () => {
    render(<Dashboard data={{ ...data, tenants: [], days: [], measuredThrough: null }} now={now} />);

    expect(screen.getByText(/No usage has been measured yet/)).toBeInTheDocument();
    expect(tile('People').getByText('14')).toBeInTheDocument();
  });
});
