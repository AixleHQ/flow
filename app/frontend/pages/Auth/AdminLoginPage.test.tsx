import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import AdminLoginPage from './AdminLoginPage';

describe('AdminLoginPage', () => {
  it('asks for an address and a password on one screen', () => {
    renderPage(<AdminLoginPage />);

    expect(screen.getByLabelText('Email')).toBeInTheDocument();
    expect(screen.getByLabelText('Password')).toBeInTheDocument();
  });

  it('posts both to /admin/login', async () => {
    const form = makeFormStub({ email: 'admin@operator.example', password: 'secret' });
    renderPage(<AdminLoginPage />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(form.post).toHaveBeenCalledWith('/admin/login');
  });

  it('refuses to post without a password', async () => {
    const form = makeFormStub({ email: 'admin@operator.example', password: '' });
    renderPage(<AdminLoginPage />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('Password is required')).toBeInTheDocument();
    expect(form.post).not.toHaveBeenCalled();
  });

  it('shows the refusal the server sends back', () => {
    const form = makeFormStub({ email: 'admin@operator.example', password: '' });
    form.errors = { password: 'Email or password is incorrect' };
    renderPage(<AdminLoginPage />, { form });

    expect(screen.getByText('Email or password is incorrect')).toBeInTheDocument();
  });
});
