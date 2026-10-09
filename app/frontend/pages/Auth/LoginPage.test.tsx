import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { act, makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import LoginPage from './LoginPage';

// Step two is what the server renders once an address has resolved to a
// workspace: it carries the address, the workspace's name, and exactly the
// methods that workspace accepts.
const stepTwo = (methods = ['password'], over = {}) => ({
  step: 'credentials',
  email: 'person@acme.test',
  companyName: 'Acme',
  methods,
  ...over,
});

describe('LoginPage', () => {
  describe('step one — the address', () => {
    it('asks for an address and nothing else', () => {
      renderPage(<LoginPage />);

      expect(screen.getByRole('textbox', { name: 'Email' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Continue' })).toBeInTheDocument();
      expect(screen.queryByLabelText('Password')).not.toBeInTheDocument();
    });

    // Nothing is offered before it can work, so there is no control to explain
    // away — which is what the old screen needed a line of small print for.
    it('offers no disabled control and no apology for one', () => {
      renderPage(<LoginPage />, { props: { oauthProviders: ['google', 'microsoft'] } });

      for (const button of screen.getAllByRole('button')) expect(button).toBeEnabled();
      expect(screen.queryByText(/the address above/)).not.toBeInTheDocument();
    });

    it('refuses an empty address', async () => {
      const form = makeFormStub({ email: '', password: '', rememberMe: false });
      renderPage(<LoginPage />, { form });

      await userEvent.click(screen.getByRole('button', { name: 'Continue' }));

      expect(await screen.findByText('Email is required')).toBeInTheDocument();
    });

    it('refuses an address that is not one', async () => {
      const form = makeFormStub({ email: 'notanemail', password: '', rememberMe: false });
      renderPage(<LoginPage />, { form });

      await userEvent.click(screen.getByRole('button', { name: 'Continue' }));

      expect(await screen.findByText('Invalid email format')).toBeInTheDocument();
    });

    it('clears the message once the address is edited', async () => {
      const form = makeFormStub({ email: '', password: '', rememberMe: false });
      renderPage(<LoginPage />, { form });

      await userEvent.click(screen.getByRole('button', { name: 'Continue' }));
      expect(await screen.findByText('Email is required')).toBeInTheDocument();

      await userEvent.type(screen.getByRole('textbox', { name: 'Email' }), 'a');

      expect(screen.queryByText('Email is required')).not.toBeInTheDocument();
    });
  });

  describe('step two — what this workspace accepts', () => {
    // Passkey is left out of these: PasswordlessOptions only draws it where the
    // browser supports WebAuthn, which jsdom does not — that gate belongs to
    // that component's own tests.
    it('draws only the methods the workspace takes', () => {
      renderPage(<LoginPage />, { props: stepTwo(['password', 'magic_link']) });

      expect(screen.getByLabelText('Password')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Email me a link' })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Google' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Microsoft' })).not.toBeInTheDocument();
    });

    it("draws the workspace's redirect providers when it takes them", () => {
      renderPage(<LoginPage />, { props: stepTwo(['google', 'microsoft']) });

      expect(screen.getByRole('button', { name: 'Google' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Microsoft' })).toBeInTheDocument();
      expect(screen.queryByLabelText('Password')).not.toBeInTheDocument();
    });

    it('offers no password box to a workspace that does not accept one', () => {
      renderPage(<LoginPage />, { props: stepTwo(['magic_link']) });

      expect(screen.queryByLabelText('Password')).not.toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Email me a link' })).toBeInTheDocument();
    });

    it('carries the address back to step one', () => {
      renderPage(<LoginPage />, { props: stepTwo() });

      expect(screen.getByRole('button', { name: 'person@acme.test' })).toBeInTheDocument();
    });

    it('says so plainly when a workspace accepts nothing at all', () => {
      renderPage(<LoginPage />, { props: stepTwo([], { dead_end: true }) });

      expect(screen.getByText(/accepts no sign-in method/)).toBeInTheDocument();
      expect(screen.queryByLabelText('Password')).not.toBeInTheDocument();
    });

    it('refuses an empty password', async () => {
      const form = makeFormStub({ email: 'person@acme.test', password: '', rememberMe: false });
      renderPage(<LoginPage />, { props: stepTwo(), form });

      await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

      expect(await screen.findByText('Password is required')).toBeInTheDocument();
      expect(form.post).not.toHaveBeenCalled();
    });

    it('posts to /login once a password is given', async () => {
      const form = makeFormStub({ email: 'person@acme.test', password: 'secret', rememberMe: false });
      renderPage(<LoginPage />, { props: stepTwo(), form });

      await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

      expect(form.post).toHaveBeenCalledWith('/login', expect.objectContaining({ onSuccess: expect.any(Function) }));
    });

    it('links a forgotten password to the reset page, carrying the address', () => {
      renderPage(<LoginPage />, { props: stepTwo() });

      expect(screen.getByRole('link', { name: 'Forgot password?' })).toHaveAttribute(
        'href',
        '/password/reset?email=person%40acme.test',
      );
    });

    it('shows the notice a finished reset lands with', async () => {
      renderPage(<LoginPage />, { props: { flash: { notice: 'Password reset. Sign in with your new password.' } } });

      expect(await screen.findByText('Password reset. Sign in with your new password.')).toBeInTheDocument();
    });

    it('toggles the password field between hidden and visible', async () => {
      renderPage(<LoginPage />, { props: stepTwo() });

      expect(screen.getByLabelText('Password')).toHaveAttribute('type', 'password');

      await userEvent.click(screen.getByRole('button', { name: 'Toggle password visibility' }));
      expect(screen.getByLabelText('Password')).toHaveAttribute('type', 'text');
    });

    it('updates the "rememberMe" form value when the checkbox is toggled', async () => {
      const form = makeFormStub({ email: 'person@acme.test', password: '', rememberMe: false });
      renderPage(<LoginPage />, { props: stepTwo(), form });

      await userEvent.click(screen.getByRole('checkbox', { name: 'Remember me' }));

      expect(form.setData).toHaveBeenCalledWith('rememberMe', true);
    });
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

    it('renders the no_workspace error screen when error is no_workspace', () => {
      renderPage(<LoginPage />, { props: { error: 'no_workspace' } });

      expect(screen.getByText('No workspace for your domain')).toBeInTheDocument();
      expect(
        screen.getByText("Your email domain isn't linked to a workspace. Contact your admin or use your work email."),
      ).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /Back to login/ })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Continue' })).not.toBeInTheDocument();
    });

    it("explains a sign-in that left the person outside their domain's workspace", () => {
      renderPage(<LoginPage />, {
        props: {
          error: 'domain_has_workspace',
          claimedDomain: {
            domain: 'acme.test',
            workspaceName: 'Acme',
            joinMethods: ['Google'],
            approvalRequired: false,
          },
        },
      });

      expect(screen.getByRole('heading', { name: 'Your domain already has a workspace' })).toBeInTheDocument();
      expect(screen.getByText(/belongs to the/)).toHaveTextContent('acme.test belongs to the Acme workspace.');
      expect(screen.getByText(/^Sign in with/)).toHaveTextContent(
        'Sign in with Google and you join Acme straight away.',
      );
      expect(screen.getByRole('link', { name: 'Back to sign in' })).toHaveAttribute('href', '/login');
      expect(screen.queryByRole('button', { name: 'Continue' })).not.toBeInTheDocument();
    });

    // The details come only with the redirect itself, so a reload or a shared
    // link still explains — without naming anyone's workspace.
    it('names no workspace once the details are gone', () => {
      renderPage(<LoginPage />, { props: { error: 'domain_has_workspace' } });

      expect(screen.getByText(/Sign in with another method it accepts/)).toBeInTheDocument();
      expect(screen.queryByText(/belongs to the/)).not.toBeInTheDocument();
    });

    it('shows a "Welcome back!" notification after a successful login', async () => {
      const form = makeFormStub({ email: 'person@acme.test', password: 'secret', rememberMe: false });
      renderPage(<LoginPage />, { props: stepTwo(), form });

      await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

      // The inert useForm stub never resolves post(); drive the onSuccess path Inertia would invoke.
      const options = (form.post as ReturnType<typeof vi.fn>).mock.calls[0][1];
      act(() => options.onSuccess?.());

      expect(await screen.findByText('Welcome back!')).toBeInTheDocument();
    });
  });

  it('pre-fills the email field from the email page prop (invitation flow)', () => {
    renderPage(<LoginPage />, { props: { email: 'invitee@client.test' } });

    expect(screen.getByLabelText('Email')).toHaveValue('invitee@client.test');
  });
});
