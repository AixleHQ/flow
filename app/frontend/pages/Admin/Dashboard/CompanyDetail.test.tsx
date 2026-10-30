import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildCompanyBreakdown, buildUsageDay } from 'test/factories/adminDashboard';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { render, screen, userEvent, within } from 'test/renderPage';

import Dashboard from './Dashboard';
import type { CompanyBreakdown, DashboardData } from './types';

const now = new Date('2026-10-19T12:00:00Z');

const data: DashboardData = {
  tenants: [{ id: 1, name: 'Acme' }],
  days: [buildUsageDay({ companyId: 1, day: '2026-10-14' })],
  measuredThrough: '2026-10-19T11:00:00Z',
  snapshot: { companies: 1, members: 3, projects: 2 },
};

const BREAKDOWN = 'GET /admin/dashboard/companies/:id.json';

async function openAcme(answer: CompanyBreakdown | Response = buildCompanyBreakdown()) {
  const fetchSpy = answerFetch({ [BREAKDOWN]: answer, 'GET /admin/dashboard/companies.json': [] });
  render(<Dashboard data={data} now={now} />);
  await userEvent.click(screen.getByRole('button', { name: 'Acme' }));
  const dialog = within(screen.getByRole('dialog', { name: 'Acme' }));
  return { dialog, fetchSpy };
}

const figure = (dialog: ReturnType<typeof within>, name: string) => within(dialog.getByRole('region', { name }));

describe('CompanyDetail', () => {
  it("opens from the company's name and reads its queue over the selected days", async () => {
    const { dialog, fetchSpy } = await openAcme();

    expect(fetchSpy).toHaveBeenCalledWith(
      '/admin/dashboard/companies/1.json?from=2026-10-01&to=2026-10-31',
      expect.objectContaining({ headers: { Accept: 'application/json' } }),
    );
    expect(dialog.getByText(/Oct 1 – Oct 31, 2026 · UTC/)).toBeInTheDocument();
    expect(dialog.getByRole('link', { name: 'Company record' })).toHaveAttribute('href', '/admin/companies/1');

    expect(await dialog.findByRole('region', { name: 'Waited over 30 s' })).toHaveTextContent('20%');
    expect(figure(dialog, 'Waited over 30 s').getByText('80 sessions')).toBeInTheDocument();
    expect(figure(dialog, 'p95 wait').getByText('10 min')).toBeInTheDocument();
    expect(figure(dialog, 'p95 of those that waited').getByText('23.3 min')).toBeInTheDocument();
    expect(dialog.getByText(/0\.3 on average, 2 at p95, 9 at most/)).toBeInTheDocument();
  });

  it('sets the average utilization beside the time every worker was busy, when the waits began', async () => {
    const { dialog } = await openAcme();

    expect(await dialog.findByRole('region', { name: 'Time at capacity' })).toHaveTextContent('6%');
    expect(figure(dialog, 'Time at capacity').getByText(/of the 720 hours it had workers/)).toBeInTheDocument();
    expect(figure(dialog, 'Waits that began at capacity').getByText('95%')).toBeInTheDocument();
    expect(figure(dialog, 'Waits that began at capacity').getByText(/76 of the 80 sessions/)).toBeInTheDocument();
    expect(figure(dialog, 'Worker limit now').getByText('2')).toBeInTheDocument();
  });

  it('shows which project the queue formed in, with the limit it had', async () => {
    const { dialog } = await openAcme();

    const support = within(await dialog.findByRole('row', { name: /^Support desk/ }));
    expect(support.getByText('1 reserved')).toBeInTheDocument();
    expect(support.getByText('15 min')).toBeInTheDocument();
    expect(within(dialog.getByRole('row', { name: /^Docs/ })).getByText('4 default')).toBeInTheDocument();
    expect(dialog.getByText(/300 runs, 1\.3 steps on average/)).toBeInTheDocument();
  });

  it('says utilization does not apply to a company that had no worker limit', async () => {
    const { dialog } = await openAcme(
      buildCompanyBreakdown({
        workerLimit: null,
        capacity: { offeredHours: 0, timeAtCapacity: null, waited: 0, waitedAtCapacity: 0 },
      }),
    );

    expect(await dialog.findByText(/No worker limit in this period/)).toBeInTheDocument();
    expect(figure(dialog, 'Worker limit now').getByText('∞')).toBeInTheDocument();
    expect(dialog.queryByRole('region', { name: 'Time at capacity' })).not.toBeInTheDocument();
  });

  it('lists each day with how many of its sessions waited and its p95', async () => {
    const { dialog } = await openAcme();

    const busy = within(await dialog.findByRole('row', { name: /^Wed, Oct 14/ }));
    expect(busy.getByText('51 of 230')).toBeInTheDocument();
    expect(busy.getByText('2h 1m')).toBeInTheDocument();
    expect(within(dialog.getByRole('row', { name: /^Tue, Oct 13/ })).getByText('0 of 12')).toBeInTheDocument();
  });

  it('closes on Escape and hands focus back to the company it was opened from', async () => {
    await openAcme();
    await screen.findByRole('region', { name: 'Sessions' });

    await userEvent.keyboard('{Escape}');

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Acme' })).toHaveFocus();
  });

  it('closes from its close button', async () => {
    const { dialog } = await openAcme();
    await dialog.findByRole('region', { name: 'Sessions' });

    await userEvent.click(dialog.getByRole('button', { name: 'Close' }));

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('says so when the breakdown cannot be loaded', async () => {
    const { dialog } = await openAcme(jsonResponse({ error: 'boom' }, 500));

    expect(await dialog.findByRole('alert')).toHaveTextContent('could not be loaded');
  });
});
