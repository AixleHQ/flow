import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import ShowPage from './ShowPage';

const props = {
  queueHourlyRate: 5,
  signedIn: false,
};

const results = () => screen.getByRole('region', { name: 'What your numbers come to' });

describe('How it works page', () => {
  it('publishes the queue price the server set, by the hour and by the month', () => {
    renderPage(<ShowPage />, { props });

    expect(screen.getByText('$5.00')).toBeInTheDocument();
    expect(screen.getByText('$3,600')).toBeInTheDocument();
  });

  it('follows the installation to a different list price', () => {
    renderPage(<ShowPage />, { props: { ...props, queueHourlyRate: 8 } });

    expect(screen.getByText('$8.00')).toBeInTheDocument();
    expect(screen.getByText('$5,760')).toBeInTheDocument();
  });

  // These are the figures the sales spreadsheet shows at its own inputs. The
  // page opens on them, so a visitor who changes nothing sees what they were
  // quoted on the call.
  it('opens on the spreadsheet defaults', () => {
    renderPage(<ShowPage />, { props });

    const panel = within(results());
    expect(panel.getByText('$217,300')).toBeInTheDocument();
    expect(panel.getByText('412.33% total ROI')).toBeInTheDocument();
    expect(panel.getByText('Pays back in 6.7 months')).toBeInTheDocument();
  });

  it('recalculates as the visitor edits their numbers', async () => {
    renderPage(<ShowPage />, { props });

    const hours = screen.getByLabelText(/Labour hours this process costs you a year/);
    await userEvent.clear(hours);
    await userEvent.type(hours, '3600');

    expect(within(results()).getByText('$484,600')).toBeInTheDocument();
  });

  // A visitor can describe a deal that never pays for itself. It has to say so.
  it('says a workload never pays back rather than showing a number', async () => {
    renderPage(<ShowPage />, { props });

    const rate = screen.getByLabelText(/Fully loaded cost of an hour/);
    await userEvent.clear(rate);
    await userEvent.type(rate, '0.25');

    expect(within(results()).getByText('Pays back in never')).toBeInTheDocument();
  });

  it('carries the queue count it worked out into the signup form', () => {
    renderPage(<ShowPage />, { props });

    expect(screen.getByRole('link', { name: /Start with 1 queue/ })).toHaveAttribute(
      'href',
      '/workspace/new?sessions=1',
    );
  });

  it('sizes the reservation up for a workload that outgrows one queue', async () => {
    renderPage(<ShowPage />, { props });

    const hours = screen.getByLabelText(/Labour hours this process costs you a year/);
    await userEvent.clear(hours);
    await userEvent.type(hours, '180000');

    expect(screen.getByRole('link', { name: /Start with 9 queues/ })).toHaveAttribute(
      'href',
      '/workspace/new?sessions=9',
    );
  });
});
