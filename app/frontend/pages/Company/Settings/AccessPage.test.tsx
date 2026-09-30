import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen } from 'test/renderPage';

import AccessPage from './AccessPage';

const deployment = (over = {}) => ({
  id: 1,
  kind: 'password',
  name: 'Password',
  scope: 'deployment',
  enabled: true,
  hasSecret: false,
  proved: true,
  ...over,
});

const connection = (over = {}) => ({
  id: 7,
  kind: 'oidc',
  name: 'Acme Okta',
  scope: 'company',
  enabled: false,
  issuer: 'https://acme.okta.com/oauth2/default',
  hasSecret: true,
  proved: false,
  ...over,
});

const joining = (over = {}) => ({
  emailDomain: 'acme.com',
  autoAcceptUsers: false,
  domainVerifiedAt: '2026-09-01T00:00:00Z',
  ...over,
});

const renderPage = (providers: unknown[], isAdmin = true, joiningState: unknown = joining()) =>
  renderAuthedPage(<AccessPage providers={providers as never} />, {
    props: {
      providers,
      joining: joiningState,
      company: { name: 'Acme' },
      permissions: { isAdmin },
      scim: { enabled: false, endpoint: '/scim' },
    },
  });

describe('Company settings — Access', () => {
  it('verifies through a real form submission, not an Inertia visit', () => {
    // Verifying redirects to the customer's identity provider. An Inertia XHR
    // cannot follow a cross-origin redirect — the browser refuses it as CORS and
    // the page sits there — so the button must submit a form that navigates.
    renderPage([deployment(), connection()]);

    const verify = screen.getByRole('button', { name: 'Verify' });
    const form = verify.closest('form');

    expect(form).toHaveAttribute('method', 'post');
    expect(form).toHaveAttribute('action', '/auth/oidc/7/start');
    expect(form?.querySelector('input[name="authenticity_token"]')).toBeInTheDocument();
  });

  it('asks for a verified domain before offering a connection or its Verify', () => {
    renderPage([deployment(), connection()], true, joining({ domainVerifiedAt: null }));

    expect(screen.queryByRole('button', { name: 'Add connection' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Verify' })).not.toBeInTheDocument();
    expect(screen.getByText(/Verify your email domain under Joining first/)).toBeInTheDocument();
  });

  it('holds an unverified connection switched off', () => {
    renderPage([deployment(), connection()]);

    expect(screen.getByText('Not verified yet')).toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Acme Okta enabled' })).toBeDisabled();
  });

  it('offers no Verify once the connection has been proved', () => {
    renderPage([deployment(), connection({ proved: true, enabled: true })]);

    expect(screen.queryByRole('button', { name: 'Verify' })).not.toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Acme Okta enabled' })).toBeEnabled();
  });

  it('shows a member what the workspace accepts, with nothing to change', () => {
    // Read-only on purpose: knowing which methods are accepted is how a member
    // understands a step-up prompt, and the page is reachable to them now that
    // it lives under Settings.
    renderPage([deployment(), connection()], false);

    expect(screen.getByRole('switch', { name: 'Password enabled' })).toBeDisabled();
    expect(screen.queryByRole('button', { name: 'Verify' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Remove' })).not.toBeInTheDocument();
    expect(screen.queryByText('Connect your own identity provider')).not.toBeInTheDocument();
  });

  it('keeps auto-join on this tab, next to the methods it belongs with', () => {
    renderPage([deployment()]);

    const autoAccept = screen.getByRole('switch', { name: 'Accept new people automatically' });
    expect(autoAccept).toBeEnabled();
    expect(screen.getByText('acme.com')).toBeInTheDocument();
  });

  it('cannot auto-join without a domain to match against', () => {
    renderPage([deployment()], true, joining({ emailDomain: null }));

    expect(screen.getByRole('switch', { name: 'Accept new people automatically' })).toBeDisabled();
    expect(screen.getByText('Not set')).toBeInTheDocument();
  });
});
