import '@testing-library/jest-dom/vitest';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { buildTenant, buildUsageDay } from 'test/factories/adminDashboard';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { render, screen, userEvent, within } from 'test/renderPage';

import Dashboard from './Dashboard';
import type { DashboardData } from './types';

const now = new Date('2026-10-19T12:00:00Z');

const data: DashboardData = {
  tenants: [
    buildTenant({ id: 1, name: 'Acme', createdAt: '2026-03-09T22:15:00Z' }),
    buildTenant({
      id: 2,
      name: 'Globex',
      createdAt: '2026-10-02T08:00:00Z',
      accountType: 'managed',
      billingMethod: null,
    }),
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
const sortBy = (name: string) => within(screen.getByRole('columnheader', { name })).getByRole('button');
const filter = (name: string) =>
  within(screen.getByRole('group', { name: 'Filters' })).getByRole('button', { name: new RegExp(`^${name}`) });

describe('Dashboard', () => {
  beforeEach(() => {
    answerFetch({ 'GET /admin/dashboard/waits.json': [] });
  });

  it('opens on the current month, one row per company, with when each was created and its status, type and billing method', () => {
    render(<Dashboard data={data} now={now} />);

    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('October 2026 (current)');
    expect(screen.getByText('Oct 14 – Oct 15, 2026 · to date · 2 companies')).toBeInTheDocument();
    const [acmeCreated, acmeStatus, acmeType, acmeMethod] = within(rowOf('Acme')).getAllByRole('cell');
    expect(acmeCreated).toHaveTextContent('Mar 9, 2026');
    expect(acmeStatus).toHaveTextContent('Active Customer');
    expect(acmeType).toHaveTextContent('Paid Account');
    expect(acmeMethod).toHaveTextContent('SaaS – Stripe');
    const [, , globexType, globexMethod] = within(rowOf('Globex')).getAllByRole('cell');
    expect(globexType).toHaveTextContent('Managed by Aixle');
    expect(globexMethod).toHaveTextContent('—');
    expect(screen.getByRole('button', { name: 'Acme' })).toBeInTheDocument();
  });

  it('sorts by account status', async () => {
    const locked = {
      ...data,
      tenants: [data.tenants[0], buildTenant({ id: 2, name: 'Globex', accountStatus: 'locked_nonpayment' })],
    };
    render(<Dashboard data={locked} now={now} />);
    const companiesInOrder = () => screen.getAllByRole('rowheader').map((cell) => cell.textContent);

    await userEvent.click(sortBy('Account status'));
    await userEvent.click(sortBy('Account status'));

    expect(companiesInOrder()).toEqual(['Globex', 'Acme', 'Total, all companies']);
    expect(within(rowOf('Globex')).getByText('Account Locked – nonpayment')).toBeInTheDocument();
  });

  it('shows the platform as it stands in tiles', () => {
    render(<Dashboard data={data} now={now} />);

    expect(tile('Companies').getByText('2')).toBeInTheDocument();
    expect(tile('Companies').getByText('1 paying · 1 managed')).toBeInTheDocument();
    expect(tile('People').getByText('14')).toBeInTheDocument();
    expect(tile('Projects').getByText('5')).toBeInTheDocument();
  });

  it('counts companies by the same account columns as the table, whichever provider bills them', () => {
    const accounts = {
      ...data,
      tenants: [
        ...data.tenants,
        buildTenant({ id: 3, name: 'Initech', billingMethod: 'saas_aws_marketplace' }),
        buildTenant({ id: 4, name: 'Hooli', accountStatus: 'trial_active', billingMethod: null }),
        buildTenant({ id: 5, name: 'Umbrella', accountStatus: 'canceled', billingMethod: 'saas_aws_marketplace' }),
      ],
      days: [...data.days, buildUsageDay({ companyId: 3, day: '2026-10-15' })],
      snapshot: { ...data.snapshot, companies: 5 },
    };
    render(<Dashboard data={accounts} now={now} />);

    expect(tile('Companies').getByText('5')).toBeInTheDocument();
    expect(tile('Companies').getByText('2 paying · 1 trial · 1 canceled · 1 managed')).toBeInTheDocument();
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
    const [, , , , workerHours, busyHours, , , , utilization] = globex.getAllByRole('cell');
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

  it('filters companies by name, and the tiles with them', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search companies' }), 'glo');

    expect(screen.queryByRole('rowheader', { name: 'Acme' })).not.toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
    expect(tile('Successful sessions').getByText('38')).toBeInTheDocument();
  });

  it('sorts by when the account was created, newest first', async () => {
    render(<Dashboard data={data} now={now} />);
    const companiesInOrder = () => screen.getAllByRole('rowheader').map((cell) => cell.textContent);

    await userEvent.click(sortBy('Account created'));
    expect(companiesInOrder()).toEqual(['Globex', 'Acme', 'Total, all companies']);

    await userEvent.click(sortBy('Account created'));
    expect(companiesInOrder()).toEqual(['Acme', 'Globex', 'Total, all companies']);
  });

  it('keeps every filter folded until it is opened, one at a time, and folds it on Escape', async () => {
    render(<Dashboard data={data} now={now} />);

    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();

    await userEvent.click(filter('Account status'));
    expect(filter('Account status')).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getAllByRole('checkbox')).toHaveLength(7);

    await userEvent.click(filter('Billing method'));
    expect(filter('Account status')).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByRole('checkbox', { name: 'No billing method' })).toBeInTheDocument();

    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    expect(filter('Billing method')).toHaveFocus();
  });

  it('names how many values a filter has once it has more than one', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(filter('Account status'));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Trial – Active' }));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Trial – Expired' }));

    expect(filter('Account status')).toHaveAccessibleName('Account status: 2 selected');
  });

  it('filters by account fields, narrowing the tiles and the total to the companies shown', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(filter('Account type'));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Managed by Aixle' }));

    expect(filter('Account type')).toHaveAccessibleName('Account type: Managed by Aixle');
    expect(screen.queryByRole('rowheader', { name: 'Acme' })).not.toBeInTheDocument();
    expect(screen.getByText('Oct 14 – Oct 15, 2026 · to date · 1 of 2 companies')).toBeInTheDocument();
    expect(tile('Companies').getByText('1')).toBeInTheDocument();
    expect(tile('Companies').getByText('1 managed')).toBeInTheDocument();
    expect(tile('Successful sessions').getByText('38')).toBeInTheDocument();
    expect(tile('Busy hours').getByText('100% not on a paid plan')).toBeInTheDocument();
    expect(tile('People').getByText('active members, all companies')).toBeInTheDocument();
    expect(within(rowOf('Total, companies shown')).getAllByText('38')).not.toHaveLength(0);
  });

  it('compares the filtered tiles with the same companies in the period before', async () => {
    const both = {
      ...data,
      days: [
        ...data.days,
        buildUsageDay({ companyId: 2, day: '2026-09-10', sessionsSucceeded: 19, billingClass: 'managed' as const }),
      ],
    };
    render(<Dashboard data={both} now={now} />);

    await userEvent.click(filter('Account type'));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Managed by Aixle' }));

    expect(tile('Successful sessions').getByText('38')).toBeInTheDocument();
    expect(tile('Successful sessions').getByText('▲ +100%')).toBeInTheDocument();
  });

  it('filters by the day the account was created', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.click(filter('Account created'));
    await userEvent.type(screen.getByLabelText('Created from'), '2026-10-01');

    expect(filter('Account created')).toHaveAccessibleName('Account created: from Oct 1, 2026');
    expect(screen.queryByRole('rowheader', { name: 'Acme' })).not.toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
  });

  it('clears the filters, keeping the search', async () => {
    render(<Dashboard data={data} now={now} />);

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search companies' }), 'a');
    await userEvent.click(filter('Account status'));
    await userEvent.click(screen.getByRole('checkbox', { name: 'Trial – Active' }));
    expect(screen.getByText('No companies match the search and filters.')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Clear filters' }));

    expect(filter('Account status')).toHaveAccessibleName('Account status');
    expect(screen.queryByRole('button', { name: 'Clear filters' })).not.toBeInTheDocument();
    expect(screen.getByRole('searchbox', { name: 'Search companies' })).toHaveValue('a');
    expect(screen.getByRole('rowheader', { name: 'Acme' })).toBeInTheDocument();
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
