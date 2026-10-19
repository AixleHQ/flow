import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildUsageDay } from 'test/factories/tenantUsage';
import { render, screen, userEvent, within } from 'test/renderPage';

import TenantUsageReport from './TenantUsageReport';
import type { TenantUsageData } from './types';

const now = new Date('2026-10-19T12:00:00Z');

const data: TenantUsageData = {
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
};

const rowOf = (name: string) => screen.getByRole('row', { name: new RegExp(`^${name}`) });

describe('TenantUsageReport', () => {
  it('opens on the current month, one row per tenant, with why each is billed or not', () => {
    render(<TenantUsageReport data={data} now={now} />);

    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('October 2026 (current)');
    expect(screen.getByText('Oct 14 – Oct 15, 2026 · to date · 2 tenants')).toBeInTheDocument();
    expect(within(rowOf('Acme')).getByText('Paying')).toBeInTheDocument();
    expect(within(rowOf('Globex')).getByText('Free · managed')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Acme' })).toHaveAttribute('href', '/admin/companies/1');
  });

  it('shows a tenant without a limit as unlimited, with no utilization', () => {
    render(<TenantUsageReport data={data} now={now} />);

    const globex = within(rowOf('Globex'));
    expect(globex.getAllByText('∞')).toHaveLength(2);
    const utilization = globex.getAllByRole('cell')[6];
    expect(utilization).toHaveTextContent(/^—/);
  });

  it('compares with the same days of the month before', () => {
    render(<TenantUsageReport data={data} now={now} />);

    expect(screen.getByText('Change vs Sep 1 – Sep 15, 2026')).toBeInTheDocument();
    expect(within(rowOf('Acme')).getByText('▲ +100%')).toBeInTheDocument();
  });

  it('steps back to the previous month', async () => {
    render(<TenantUsageReport data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Previous period' }));

    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('September 2026');
    expect(screen.getByRole('rowheader', { name: 'Acme' })).toBeInTheDocument();
    expect(screen.queryByRole('rowheader', { name: 'Globex' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Previous period' })).toBeDisabled();
  });

  it('switches to a single day', async () => {
    render(<TenantUsageReport data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Day' }));

    expect(screen.getByRole('button', { name: 'Day' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('combobox', { name: 'Period' })).toHaveDisplayValue('Thu, Oct 15, 2026');
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
  });

  it('sums a custom range', async () => {
    render(<TenantUsageReport data={data} now={now} />);

    await userEvent.click(screen.getByRole('button', { name: 'Custom' }));

    expect(screen.getByLabelText('From')).toHaveValue('2026-10-01');
    expect(screen.getByLabelText('To')).toHaveValue('2026-10-19');
    expect(screen.getByText('Oct 1 – Oct 19, 2026 · custom range · 2 tenants')).toBeInTheDocument();
  });

  it('filters tenants by name', async () => {
    render(<TenantUsageReport data={data} now={now} />);

    await userEvent.type(screen.getByRole('searchbox', { name: 'Search tenants' }), 'glo');

    expect(screen.queryByRole('rowheader', { name: 'Acme' })).not.toBeInTheDocument();
    expect(screen.getByRole('rowheader', { name: 'Globex' })).toBeInTheDocument();
  });

  it('sorts by a column, and reverses on a second click', async () => {
    render(<TenantUsageReport data={data} now={now} />);
    const tenantsInOrder = () => screen.getAllByRole('rowheader').map((cell) => cell.textContent);

    await userEvent.click(screen.getByRole('button', { name: 'Successful sessions' }));
    expect(tenantsInOrder()).toEqual(['Globex', 'Acme', 'Total, all tenants']);

    await userEvent.click(screen.getByRole('button', { name: 'Successful sessions' }));
    expect(tenantsInOrder()).toEqual(['Acme', 'Globex', 'Total, all tenants']);
    expect(screen.getByRole('columnheader', { name: /Successful sessions/ })).toHaveAttribute('aria-sort', 'ascending');
  });

  it('totals the period across tenants', () => {
    render(<TenantUsageReport data={data} now={now} />);

    const totals = within(rowOf('Total, all tenants'));
    expect(totals.getByText('58')).toBeInTheDocument();
  });

  it('says so when nothing has been measured yet', () => {
    render(<TenantUsageReport data={{ tenants: [], days: [], measuredThrough: null }} now={now} />);

    expect(screen.getByText(/No usage has been measured yet/)).toBeInTheDocument();
  });
});
