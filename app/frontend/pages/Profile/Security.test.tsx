import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import SecurityPage from './Security';

const QR_DATA_URI = 'data:image/svg+xml;base64,PHN2Zy8+';
const SECRET = 'JBSWY3DPEHPK3PXP';

// The enrolment payload is a plain `render json:`, not an Inertia response, so
// its keys stay as the server spells them — snake_case.
const stubEnrolment = (body: Record<string, unknown>) =>
  vi.spyOn(globalThis, 'fetch').mockResolvedValue({
    ok: true,
    json: async () => body,
  } as Response);

const renderPage = (totpEnabled = false) =>
  renderAuthedPage(<SecurityPage passkeys={[]} totpEnabled={totpEnabled} sessions={[]} />, {
    props: { passkeys: [], totpEnabled, sessions: [] },
  });

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
