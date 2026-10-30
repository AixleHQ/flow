import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildSharedPermissions, buildSharedTrial } from 'test/factories/sharedProps';
import { renderPage, screen } from 'test/renderPage';

import { TrialBanner } from './TrialBanner';

const trial = buildSharedTrial();
const admin = buildSharedPermissions();
const blocked = buildSharedTrial({ state: 'blocked', daysLeft: 0 });

describe('TrialBanner', () => {
  // Sent only while a trial is running or has ended, so everyone else must see
  // nothing at all rather than an empty bar.
  it('is not drawn for a workspace somebody is paying for', () => {
    renderPage(<TrialBanner />, { props: {} });

    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('says how many days are left and which is the last', () => {
    renderPage(<TrialBanner />, { props: { trial } });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('You are on the free trial, on one worker: 21 days left');
    expect(banner).toHaveTextContent('the last day is Nov 20, 2026');
  });

  // ── Running out ─────────────────────────────────────────────────────────

  it('leads with the deadline in the last few days', () => {
    renderPage(<TrialBanner />, { props: { trial: buildSharedTrial({ daysLeft: 3, lastDay: '2026-11-02' }) } });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('The free trial ends in 3 days — the last day is Nov 2, 2026');
    expect(banner).toHaveTextContent('After that, no new sessions start');
  });

  it('says so on the last day', () => {
    renderPage(<TrialBanner />, { props: { trial: buildSharedTrial({ daysLeft: 1 }) } });

    expect(screen.getByRole('status')).toHaveTextContent('Today is the last day of the free trial.');
  });

  // ── Paying ──────────────────────────────────────────────────────────────

  it('offers an administrator a card to add', () => {
    renderPage(<TrialBanner />, { props: { trial, permissions: admin } });

    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  it('presses for the card once the trial is running out', () => {
    renderPage(<TrialBanner />, { props: { trial: buildSharedTrial({ daysLeft: 2 }), permissions: admin } });

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
    expect(screen.getByRole('status')).toHaveTextContent('21 days left');
  });

  it('says plainly when the trial is over', () => {
    renderPage(<TrialBanner />, { props: { trial: blocked } });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('Your free trial has ended');
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

  it('says the subscription ended rather than that the trial did', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...blocked, status: 'canceled' as const }, permissions: admin },
    });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('Your subscription has ended');
    expect(banner).not.toHaveTextContent('free trial');
    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  it('points at us when there is not', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...blocked, canPay: false }, permissions: admin },
    });

    expect(screen.getByRole('status')).toHaveTextContent('Talk to us to carry on');
  });
});
