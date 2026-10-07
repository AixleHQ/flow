import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { TrialBanner } from './TrialBanner';

const trial = {
  state: 'trialing' as const,
  allowanceHours: 100,
  usedHours: 60,
  remainingHours: 40,
  maxSessions: 10,
  hoursLeftAtCurrentRate: 4,
  canPay: true,
};

const admin = { isAdmin: true, canManageMembers: true, canManageProjects: true };

describe('TrialBanner', () => {
  // Sent only while an allowance is running or spent, so everyone else must see
  // nothing at all rather than an empty bar.
  it('is not drawn for a workspace somebody is paying for', () => {
    renderPage(<TrialBanner />, { props: {} });

    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it('says what has been spent and what is left', () => {
    renderPage(<TrialBanner />, { props: { trial } });

    expect(screen.getByRole('status')).toHaveTextContent('60 of 100 worker-hours used');
  });

  // The allowance is a quantity and the workspace sets the rate: forty hours is
  // four days at one session and four hours at ten. Only the second number
  // answers "when do I have to do something about this".
  it('turns what is left into hours at the rate they are running', () => {
    renderPage(<TrialBanner />, { props: { trial } });

    expect(screen.getByRole('status')).toHaveTextContent('At 10 workers that is about 4 hours left');
  });

  it('says one session without the plural', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...trial, maxSessions: 1, hoursLeftAtCurrentRate: 40 } },
    });

    expect(screen.getByRole('status')).toHaveTextContent('At 1 worker that is about 40 hours left');
  });

  // A workspace with no limit has no rate to divide by, and inventing one would
  // be worse than saying nothing.
  it('leaves the estimate out when there is no limit to run at', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...trial, maxSessions: null, hoursLeftAtCurrentRate: null } },
    });

    expect(screen.getByRole('status')).toHaveTextContent('60 of 100 worker-hours used');
    expect(screen.queryByText(/hours left/)).not.toBeInTheDocument();
  });

  // ── Paying ──────────────────────────────────────────────────────────────

  it('offers an administrator a card to add', () => {
    renderPage(<TrialBanner />, { props: { trial, permissions: admin } });

    expect(screen.getByRole('button', { name: 'Add a card' })).toBeInTheDocument();
  });

  // A member can see where the workspace stands without being offered a button
  // the server would refuse.
  it('offers no button to somebody who may not press it', () => {
    renderPage(<TrialBanner />, { props: { trial, permissions: { ...admin, isAdmin: false } } });

    expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
  });

  // An installation with no payment provider must not offer a button that leads
  // nowhere.
  it('offers no button where there is nowhere to pay', () => {
    renderPage(<TrialBanner />, { props: { trial: { ...trial, canPay: false }, permissions: admin } });

    expect(screen.queryByRole('button', { name: 'Add a card' })).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('60 of 100 worker-hours used');
  });

  it('says plainly when the allowance is gone', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...trial, state: 'blocked' as const, usedHours: 100, remainingHours: 0 } },
    });

    const banner = screen.getByRole('status');
    expect(banner).toHaveTextContent('used all 100 of your free worker-hours');
    expect(banner).toHaveTextContent('Anything already running finishes');
  });

  // The way out has to match the button beside it: offering "talk to us" next to
  // an "Add a card" button reads as two different answers.
  it('points at the card when there is one to add', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...trial, state: 'blocked' as const }, permissions: admin },
    });

    expect(screen.getByRole('status')).toHaveTextContent('Add a card to carry on');
  });

  it('points at us when there is not', () => {
    renderPage(<TrialBanner />, {
      props: { trial: { ...trial, state: 'blocked' as const, canPay: false }, permissions: admin },
    });

    expect(screen.getByRole('status')).toHaveTextContent('Talk to us to carry on');
  });
});
