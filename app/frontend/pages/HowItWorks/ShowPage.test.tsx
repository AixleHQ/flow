import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import ShowPage from './ShowPage';

const props = {
  queueHourlyRate: 5,
  trialDays: 30,
  signedIn: false,
};

const results = () => screen.getByRole('region', { name: 'What your numbers come to' });
// The list price and the calculator's own effective-cost row can carry the same
// figure, so a price assertion has to say which one it means.
const prices = () => screen.getByRole('region', { name: 'What it costs' });

describe('How it works page', () => {
  it('publishes the worker price the server set, by the hour and by the month', () => {
    renderPage(<ShowPage />, { props });

    expect(within(prices()).getByText('$5.00')).toBeInTheDocument();
    expect(within(prices()).getByText('$3,600')).toBeInTheDocument();
  });

  it('says how long a new workspace is free', () => {
    renderPage(<ShowPage />, { props });

    expect(within(prices()).getByText('30')).toBeInTheDocument();
    expect(within(prices()).getByText('days free')).toBeInTheDocument();
  });

  it('follows the installation to a different list price', () => {
    renderPage(<ShowPage />, { props: { ...props, queueHourlyRate: 8 } });

    expect(within(prices()).getByText('$8.00')).toBeInTheDocument();
    expect(within(prices()).getByText('$5,760')).toBeInTheDocument();
  });

  // These are the figures the sales spreadsheet shows at its own inputs. The
  // page opens on them, so a visitor who changes nothing sees what they were
  // quoted on the call.
  it('opens on the spreadsheet defaults', () => {
    renderPage(<ShowPage />, { props });

    const panel = within(results());
    expect(panel.getByText('$274,000')).toBeInTheDocument();
    expect(panel.getByText('318.60% ROI')).toBeInTheDocument();
    expect(panel.getByText('Pays back in 7.4 months')).toBeInTheDocument();
    expect(panel.getByText('158.36%')).toBeInTheDocument();
  });

  it('recalculates as the visitor edits their numbers', async () => {
    renderPage(<ShowPage />, { props });

    const hours = screen.getByLabelText(/Labour hours this process costs you a year/);
    await userEvent.clear(hours);
    await userEvent.type(hours, '3600');

    expect(within(results()).getByText('$598,000')).toBeInTheDocument();
  });

  // A visitor can describe a deal that never pays for itself. It has to say so.
  it('says a workload never pays back rather than showing a number', async () => {
    renderPage(<ShowPage />, { props });

    const rate = screen.getByLabelText(/Fully loaded cost of an hour/);
    await userEvent.clear(rate);
    await userEvent.type(rate, '2');

    expect(within(results()).getByText('Pays back in never')).toBeInTheDocument();
  });

  // The trial runs one worker whatever the workload, so nothing is carried over.
  it('sends the visitor to the signup form to start the trial', () => {
    renderPage(<ShowPage />, { props });

    expect(screen.getByRole('link', { name: 'Start the free trial' })).toHaveAttribute('href', '/workspace/new');
  });

  it('sizes the reservation up for a workload that outgrows one worker', async () => {
    renderPage(<ShowPage />, { props });

    const hours = screen.getByLabelText(/Labour hours this process costs you a year/);
    await userEvent.clear(hours);
    await userEvent.type(hours, '18000');

    expect(screen.getByText('9 workers')).toBeInTheDocument();
  });
});
