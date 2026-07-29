import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import InvitationShow from './Show';

const baseProps = {
  token: 'tok-123',
  company: { name: 'Globex Labs' },
  role: 'viewer',
  inviterName: 'Nova Stargazer',
  invitedEmail: 'invitee@client.test',
};

describe('Invitations/Show', () => {
  afterEach(() => vi.clearAllMocks());

  it('renders the expired variant with a login escape hatch', () => {
    renderPage(<InvitationShow variant="expired" token="tok-123" />);

    expect(screen.getByText(/invitation link is no longer valid/i)).toBeInTheDocument();
  });

  it('accept variant posts accept and decline to the token routes', async () => {
    renderPage(<InvitationShow variant="accept" {...baseProps} />);

    expect(screen.getByText(/join globex labs/i)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /accept invitation/i }));
    expect(router.post).toHaveBeenCalledWith('/invitations/tok-123/accept');

    await userEvent.click(screen.getByRole('button', { name: /decline/i }));
    expect(router.post).toHaveBeenCalledWith('/invitations/tok-123/decline');
  });

  it('wrong_account variant names both emails and logs out before re-visiting', async () => {
    renderPage(<InvitationShow variant="wrong_account" {...baseProps} currentEmail="someone-else@acme.test" />);

    expect(screen.getByText('invitee@client.test')).toBeInTheDocument();
    expect(screen.getByText('someone-else@acme.test')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /log out and continue/i }));
    expect(router.delete).toHaveBeenCalledWith('/logout', expect.objectContaining({ onFinish: expect.any(Function) }));
  });

  it('login variant points the invitee at the login page with the email pre-filled', async () => {
    renderPage(<InvitationShow variant="login" {...baseProps} />);

    expect(screen.getByText(/it will be applied automatically/i)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /sign in to accept/i }));
    expect(router.visit).toHaveBeenCalledWith('/login?email=invitee%40client.test');
  });

  it('signup variant renders the prefilled name and password fields', () => {
    renderPage(<InvitationShow variant="signup" {...baseProps} inviteeName="Client Viewer" />);

    expect(screen.getByText(/or create a password to get started/i)).toBeInTheDocument();
    expect(screen.getByDisplayValue('Client Viewer')).toBeInTheDocument();
    expect(screen.getByLabelText(/^password$/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/confirm password/i)).toBeInTheDocument();
  });

  it('signup variant offers Google OAuth as an alternative to the password form', () => {
    renderPage(<InvitationShow variant="signup" {...baseProps} inviteeName="Client Viewer" />);

    // Google sign-in is a POST form with a CSRF token, not a plain GET link — a
    // GET /auth/google can be triggered on a victim's session from an external
    // page (see config/initializers/omniauth.rb).
    const googleButton = screen.getByRole('button', { name: /continue with google/i });
    expect(googleButton).toHaveAttribute('type', 'submit');
    expect(googleButton.closest('form')).toHaveAttribute('action', '/auth/google');
  });
});
