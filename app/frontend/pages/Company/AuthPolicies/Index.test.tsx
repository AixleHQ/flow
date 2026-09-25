import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen } from 'test/renderPage';

import AuthPoliciesIndex from './Index';

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

const renderPage = (providers: unknown[], isAdmin = true) =>
  renderAuthedPage(<AuthPoliciesIndex providers={providers as never} />, {
    props: { providers, permissions: { isAdmin }, scim: { enabled: false, endpoint: '/scim' } },
  });

describe('Company sign-in methods', () => {
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

  it('gives a member no way to change anything', () => {
    renderPage([deployment(), connection()], false);

    expect(screen.queryByRole('button', { name: 'Verify' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Remove' })).not.toBeInTheDocument();
    expect(screen.getByRole('switch', { name: 'Password enabled' })).toBeDisabled();
  });
});
