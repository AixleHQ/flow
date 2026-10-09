import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import PasswordResetPage from './PasswordResetPage';
import PasswordResetRequestPage from './PasswordResetRequestPage';

describe('PasswordResetRequestPage', () => {
  it('asks for the address, prefilled from the sign-in screen', async () => {
    renderPage(<PasswordResetRequestPage email="person@acme.test" sent={false} />);

    expect(screen.getByRole('textbox', { name: 'Email' })).toHaveValue('person@acme.test');
    await userEvent.click(screen.getByRole('button', { name: 'Send reset link' }));

    expect(router.post).toHaveBeenCalledWith('/password/reset', { email: 'person@acme.test' }, expect.anything());
  });

  it('confirms without saying whether the address has an account', () => {
    renderPage(<PasswordResetRequestPage sent />);

    expect(screen.getByRole('heading', { name: 'Check your email' })).toBeInTheDocument();
    expect(screen.getByText(/If that address belongs to an account/)).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: 'Email' })).not.toBeInTheDocument();
  });
});

describe('PasswordResetPage', () => {
  it('saves a new password against the link it was opened from', async () => {
    renderPage(<PasswordResetPage token="abc/def+gh==--sig" valid minLength={8} />);

    await userEvent.type(screen.getByLabelText('New password'), 'Sunflower42');
    await userEvent.type(screen.getByLabelText('Confirm password'), 'Sunflower42');
    await userEvent.click(screen.getByRole('button', { name: 'Save password' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/password/reset/abc%2Fdef%2Bgh%3D%3D--sig',
      { password: 'Sunflower42', passwordConfirmation: 'Sunflower42' },
      expect.anything(),
    );
  });

  it('refuses a mismatch before asking the server', async () => {
    renderPage(<PasswordResetPage token="t" valid minLength={8} />);

    await userEvent.type(screen.getByLabelText('New password'), 'Sunflower42');
    await userEvent.type(screen.getByLabelText('Confirm password'), 'Sunflower43');
    await userEvent.click(screen.getByRole('button', { name: 'Save password' }));

    expect(await screen.findByText('The passwords do not match.')).toBeInTheDocument();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('offers a new link once this one is spent', () => {
    renderPage(<PasswordResetPage token="t" valid={false} minLength={8} />);

    expect(screen.getByRole('heading', { name: 'This link no longer works' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Send a new link' })).toHaveAttribute('href', '/password/reset');
    expect(screen.queryByLabelText('New password')).not.toBeInTheDocument();
  });
});
