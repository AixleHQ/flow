import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import LoginPage from './LoginPage';

describe('LoginPage', () => {
  it('shows validation errors and does NOT submit when fields are empty', async () => {
    const form = makeFormStub({ email: '', password: '', rememberMe: false });
    renderPage(<LoginPage />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText('Email is required')).toBeInTheDocument();
    expect(screen.getByText('Password is required')).toBeInTheDocument();
    expect(form.post).not.toHaveBeenCalled();
  });

  it('posts to /login when data is valid (pre-seeded — the useForm stub is non-reactive)', async () => {
    const form = makeFormStub({ email: 'a@b.com', password: 'secret', rememberMe: false });
    renderPage(<LoginPage />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(form.post).toHaveBeenCalledWith('/login', expect.objectContaining({ onSuccess: expect.any(Function) }));
  });
});
