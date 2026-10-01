import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import SecurityPage from './Security';

type SignInMethod = Parameters<typeof SecurityPage>[0]['signInMethods'][number];

const buildMethod = (overrides: Partial<SignInMethod> = {}): SignInMethod => ({
  id: 1,
  kind: 'password',
  name: 'Password',
  email: 'me@acme.test',
  lastUsedAt: '2026-09-30T10:00:00Z',
  removable: false,
  removalRefusal: null,
  ...overrides,
});

const QR_DATA_URI = 'data:image/svg+xml;base64,PHN2Zy8+';
const SECRET = 'JBSWY3DPEHPK3PXP';

// The enrolment payload is a plain `render json:`, not an Inertia response, so
// its keys stay as the server spells them — snake_case.
const stubEnrolment = (body: Record<string, unknown>) =>
  vi.spyOn(globalThis, 'fetch').mockResolvedValue({
    ok: true,
    json: async () => body,
  } as Response);

const renderPage = (
  totpEnabled = false,
  { signInMethods = [buildMethod()], linkableKinds = ['google', 'microsoft'] } = {},
) =>
  renderAuthedPage(
    <SecurityPage
      signInMethods={signInMethods}
      linkableKinds={linkableKinds}
      passkeys={[]}
      totpEnabled={totpEnabled}
      sessions={[]}
    />,
    { props: { signInMethods, linkableKinds, passkeys: [], totpEnabled, sessions: [] } },
  );

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Profile Security tab', () => {
  it('shows the QR to scan and the secret to type once enrolment starts', async () => {
    stubEnrolment({ secret: SECRET, qr_code: QR_DATA_URI, provisioning_uri: `otpauth://totp/x?secret=${SECRET}` });
    renderPage();

    expect(screen.queryByRole('img', { name: /QR code/i })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Set up' }));

    expect(await screen.findByRole('img', { name: /QR code/i })).toHaveAttribute('src', QR_DATA_URI);
    // The typed fallback matters as much as the QR: a desktop authenticator has
    // no camera to point at the screen.
    expect(screen.getByText(SECRET)).toBeInTheDocument();
  });

  it('still offers the secret when the server sends no QR', async () => {
    stubEnrolment({ secret: SECRET, provisioning_uri: `otpauth://totp/x?secret=${SECRET}` });
    renderPage();

    await userEvent.click(screen.getByRole('button', { name: 'Set up' }));

    expect(await screen.findByText(SECRET)).toBeInTheDocument();
    expect(screen.queryByRole('img', { name: /QR code/i })).not.toBeInTheDocument();
  });

  it('offers no enrolment once codes are already on', () => {
    renderPage(true);

    expect(screen.queryByRole('button', { name: 'Set up' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Turn off' })).toBeInTheDocument();
  });
});

describe('Profile Security tab — sign-in methods', () => {
  it('lists every way in with the address it carried and whether it has been used', () => {
    renderPage(false, {
      signInMethods: [
        buildMethod(),
        buildMethod({ id: 2, kind: 'microsoft', name: 'Microsoft', email: 'me@contoso.example', lastUsedAt: null }),
      ],
    });

    expect(screen.getByRole('heading', { name: 'Sign-in methods' })).toBeInTheDocument();
    expect(screen.getByText('Password')).toBeInTheDocument();
    expect(screen.getByText('Microsoft')).toBeInTheDocument();
    expect(screen.getByText(/me@contoso\.example · not used yet/)).toBeInTheDocument();
    expect(screen.getByText(/me@acme\.test · last used/)).toBeInTheDocument();
  });

  it('links through a real POST form that carries only the kind', () => {
    // A real form, not an Inertia visit: linking ends on the provider's own page,
    // which an XHR cannot follow. The intent itself is kept on the server.
    renderPage(false, { linkableKinds: ['microsoft'] });

    const form = screen.getByRole('form', { name: 'Link Microsoft' });
    expect(form).toHaveAttribute('method', 'post');
    expect(form).toHaveAttribute('action', '/profile/sign_in_methods');
    expect(form).toHaveFormValues({ kind: 'microsoft' });
    expect(screen.getByRole('button', { name: 'Link Microsoft' })).toHaveAttribute('type', 'submit');
    expect(screen.queryByRole('button', { name: 'Link Google' })).not.toBeInTheDocument();
  });

  it('offers nothing to link when no company of theirs accepts a redirect provider', () => {
    renderPage(false, { linkableKinds: [] });

    expect(screen.queryByRole('button', { name: /^Link / })).not.toBeInTheDocument();
  });

  it('removes a linked method with a DELETE', async () => {
    renderPage(false, {
      signInMethods: [buildMethod(), buildMethod({ id: 7, kind: 'google', name: 'Google', removable: true })],
    });

    await userEvent.click(screen.getByRole('button', { name: 'Remove Google (me@acme.test)' }));

    expect(router.delete).toHaveBeenCalledWith('/profile/sign_in_methods/7');
  });

  it('says why a method cannot be removed instead of letting the request fail', async () => {
    const refusal = 'Google is your only sign-in method that Acme accepts. Link another method it accepts first.';
    renderPage(false, {
      signInMethods: [buildMethod({ id: 7, kind: 'google', name: 'Google', removable: true, removalRefusal: refusal })],
    });

    const remove = screen.getByRole('button', { name: 'Remove Google (me@acme.test)' });
    expect(remove).toBeDisabled();
    expect(screen.getByText(refusal)).toBeInTheDocument();

    await userEvent.click(remove);
    expect(router.delete).not.toHaveBeenCalled();
  });

  it('has no Remove for a method managed by its own credential', () => {
    renderPage(false, { signInMethods: [buildMethod()] });

    expect(screen.queryByRole('button', { name: /^Remove Password/ })).not.toBeInTheDocument();
  });
});
