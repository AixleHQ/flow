import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildSharedPermissions, buildSharedTrial } from 'test/factories/sharedProps';
import { renderPage, screen } from 'test/renderPage';

import { TrialBanner } from './TrialBanner';

const trial = buildSharedTrial();
const admin = buildSharedPermissions();
const blocked = buildSharedTrial({ state: 'blocked', usedHours: 100, remainingHours: 0, hoursLeftAtCurrentRate: 0 });

describe('TrialBanner', () => {
  // Sent only while an allowance is running or spent, so everyone else must see
  // nothing at all rather than an empty bar.
  it('is not drawn for a workspace somebody is paying for', () => {
    renderPage(<TrialBanner />, { props: {} });

    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('says what has been spent and what is left', () => {
    renderPage(<TrialBanner />, { props: { trial } });

    expect(screen.getByRole('status')).toHaveTextContent('30 of 100 worker-hours used');
  });

  // The allowance is a quantity and the workspace sets the rate: forty hours is
  // four days at one session and four hours at ten. Only the second number
  // answers "when do I have to do something about this".
  it('turns what is left into hours at the rate they are running', () => {
    renderPage(<TrialBanner />, { props: { trial } });

    expect(screen.getByRole('status')).toHaveTextContent('At 2 workers that is about 35 hours left');
  });

  it('says one session without the plural', () => {
    renderPage(<TrialBanner />, {
      props: { trial: buildSharedTrial({ maxSessions: 1, hoursLeftAtCurrentRate: 70 }) },
    });

    expect(screen.getByRole('status')).toHaveTextContent('At 1 worker that is about 70 hours left');
  });

  // A workspace with no limit has no rate to divide by, and inventing one would
  // be worse than saying nothing.
  it('leaves the estimate out when there is no limit to run at', () => {
    renderPage(<TrialBanner />, {
      props: { trial: buildSharedTrial({ maxSessions: null, hoursLeftAtCurrentRate: null }) },
    });

    expect(screen.getByRole('status')).toHaveTextContent('30 of 100 worker-hours used');
    expect(screen.queryByText(/hours left/)).not.toBeInTheDocument();
  });

  // ── Running out ─────────────────────────────────────────────────────────

  // Forty hours is plenty at one worker and an afternoon at ten: the deadline,
  // not the share spent, is what makes it urgent.
  it('leads with the deadline once less than a day is left at the current rate', () => {
    renderPage(<TrialBanner />, {
      props: {
        trial: buildSharedTrial({ usedHours: 60, remainingHours: 40, maxSessions: 10, hoursLeftAtCurrentRate: 4 }),
      },
    });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('Free capacity runs out in about 4 hours at 10 workers');
    expect(banner).toHaveTextContent('After that, no new sessions start');
  });

  it('says one hour without the plural', () => {
    renderPage(<TrialBanner />, {
      props: {
        trial: buildSharedTrial({ maxSessions: 1, hoursLeftAtCurrentRate: 1, usedHours: 99, remainingHours: 1 }),
      },
    });

    expect(screen.getByRole('status')).toHaveTextContent('runs out in about 1 hour at 1 worker');
  });

  it('warns by the share spent when there is no limit to time it by', () => {
    renderPage(<TrialBanner />, {
      props: {
        trial: buildSharedTrial({ usedHours: 90, remainingHours: 10, maxSessions: null, hoursLeftAtCurrentRate: null }),
      },
    });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('Free capacity is almost gone');
    expect(banner).toHaveTextContent('90 of 100 worker-hours used');
  });

  // ── Paying ──────────────────────────────────────────────────────────────

  it('offers an administrator a card to add', () => {
    renderPage(<TrialBanner />, { props: { trial, permissions: admin } });

    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  it('presses for the card once the allowance is running out', () => {
    renderPage(<TrialBanner />, {
      props: {
        trial: buildSharedTrial({ usedHours: 90, remainingHours: 10, hoursLeftAtCurrentRate: 5 }),
        permissions: admin,
      },
    });

    expect(screen.getByRole('button', { name: 'Add a card now' })).toBeInTheDocument();
  });

  // A member can see where the workspace stands without being offered a button
  // the server would refuse.
  it('offers no button to somebody who may not press it', () => {
    renderPage(<TrialBanner />, { props: { trial, permissions: buildSharedPermissions({ isAdmin: false }) } });

    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  // An installation with no payment provider must not offer a button that leads
  // nowhere.
  it('offers no button where there is nowhere to pay', () => {
    renderPage(<TrialBanner />, { props: { trial: buildSharedTrial({ canPay: false }), permissions: admin } });

    expect(screen.queryByRole('button')).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('30 of 100 worker-hours used');
  });

  it('says plainly when the allowance is gone', () => {
    renderPage(<TrialBanner />, { props: { trial: blocked } });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('used all 100 of your free worker-hours');
    expect(banner).toHaveTextContent('Anything already running finishes');
  });

  // The way out has to match the button beside it: offering "talk to us" next to
  // an "Add a card" button reads as two different answers.
  it('points at the card when there is one to add', () => {
    renderPage(<TrialBanner />, { props: { trial: blocked, permissions: admin } });

    expect(screen.getByRole('status')).toHaveTextContent('Add a card to carry on');
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  // Paying the open invoice undoes a failed payment; a new card would open a
  // second subscription and bill the same minutes twice.
  it('offers the open invoice, not a new card, after a failed payment', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...blocked, status: 'payment_failed' as const }, permissions: admin },
    });

    expect(screen.getByRole('status')).toHaveTextContent('Your last payment did not go through');
    expect(screen.getByRole('button', { name: 'Pay invoice' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Add a card/ })).not.toBeInTheDocument();
  });

  it('says the subscription ended rather than that free hours ran out', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...blocked, status: 'canceled' as const }, permissions: admin },
    });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('Your subscription has ended');
    expect(banner).not.toHaveTextContent('free worker-hours');
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  it('points at us when there is not', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...blocked, canPay: false }, permissions: admin },
    });

    expect(screen.getByRole('status')).toHaveTextContent('Talk to us to carry on');
  });
});
