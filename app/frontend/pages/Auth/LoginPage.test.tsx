import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { act, makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

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

  it('shows "Invalid email format" and does NOT submit when the email is malformed', async () => {
    const form = makeFormStub({ email: 'notanemail', password: 'secret', rememberMe: false });
    renderPage(<LoginPage />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    // min(1) passes so the "required" branch is skipped; the .email() refinement fails instead.
    expect(await screen.findByText('Invalid email format')).toBeInTheDocument();
    expect(form.post).not.toHaveBeenCalled();
  });

  it('clears a field validation error once the user edits that field', async () => {
    const form = makeFormStub({ email: '', password: '', rememberMe: false });
    renderPage(<LoginPage />, { form });

    // First trip the client-side validation branch so both messages are on screen.
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));
    expect(await screen.findByText('Email is required')).toBeInTheDocument();
    expect(screen.getByText('Password is required')).toBeInTheDocument();

    // Editing each field runs its onChange "clear this field's error" branch. The useForm stub is
    // non-reactive so the displayed value stays empty, but setClientErrors re-renders and drops the
    // message — that state update is what we assert.
    await userEvent.type(screen.getByRole('textbox', { name: 'Email' }), 'a');
    await userEvent.type(screen.getByLabelText('Password'), 'x');

    expect(screen.queryByText('Email is required')).not.toBeInTheDocument();
    expect(screen.queryByText('Password is required')).not.toBeInTheDocument();
  });

  it('toggles the password field between hidden and visible', async () => {
    renderPage(<LoginPage />);

    expect(screen.getByLabelText('Password')).toHaveAttribute('type', 'password');

    await userEvent.click(screen.getByRole('button', { name: 'Toggle password visibility' }));
    expect(screen.getByLabelText('Password')).toHaveAttribute('type', 'text');

    await userEvent.click(screen.getByRole('button', { name: 'Toggle password visibility' }));
    expect(screen.getByLabelText('Password')).toHaveAttribute('type', 'password');
  });

  it('updates the "rememberMe" form value when the checkbox is toggled', async () => {
    const form = makeFormStub({ email: '', password: '', rememberMe: false });
    renderPage(<LoginPage />, { form });

    await userEvent.click(screen.getByRole('checkbox', { name: 'Remember me' }));

    expect(form.setData).toHaveBeenCalledWith('rememberMe', true);
  });

  describe('server-driven and success notifications', () => {
    // The @mantine/notifications store is a module-level singleton that outlives cleanup(); reset it
    // before each case so a toast from one test cannot leak into the next.
    beforeEach(() => notifications.clean());

    it('shows the mapped notification for a known error code', async () => {
      renderPage(<LoginPage />, { props: { error: 'pending_approval' } });

      expect(
        await screen.findByText('Your account is pending approval. Please contact your company administrator.'),
      ).toBeInTheDocument();
    });

    it('shows a generic notification for an unrecognized error code', async () => {
      renderPage(<LoginPage />, { props: { error: 'totally_unknown' } });

      expect(await screen.findByText('Authentication failed. Please try again.')).toBeInTheDocument();
    });

    it('shows no notification when there is no error prop', () => {
      renderPage(<LoginPage />);

      expect(screen.queryByText(/Authentication failed/)).not.toBeInTheDocument();
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });

    it('shows a "Welcome back!" notification after a successful login', async () => {
      const form = makeFormStub({ email: 'a@b.com', password: 'secret', rememberMe: false });
      renderPage(<LoginPage />, { form });

      await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

      // The inert useForm stub never resolves post(); drive the onSuccess path Inertia would invoke.
      const options = (form.post as ReturnType<typeof vi.fn>).mock.calls[0][1];
      act(() => options.onSuccess?.());

      expect(await screen.findByText('Welcome back!')).toBeInTheDocument();
    });
  });
});
