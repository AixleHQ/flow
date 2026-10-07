import '@testing-library/jest-dom/vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { answerFetch, jsonResponse } from 'test/fetchStub';
import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { YoutrackConnectModal } from './YoutrackConnectModal';

const BASE = '/company/projects/1/integrations';
const MARKETPLACE = 'https://plugins.jetbrains.com/plugin/aixle-flow';
const REDIRECT = 'https://acme.youtrack.cloud/admin/app/aixle-flow/connect#app_pairing=p1.s3cret';

const renderModal = () =>
  renderPage(
    <YoutrackConnectModal
      opened
      onClose={() => {}}
      basePath={BASE}
      youtrack={{ enabled: true, marketplaceUrl: MARKETPLACE }}
    />,
  );

describe('YoutrackConnectModal', () => {
  // window.location is read-only in jsdom; swap it for a plain object so the
  // navigation to YouTrack can be observed.
  const originalLocation = window.location;
  const assign = vi.fn();

  beforeEach(() => {
    assign.mockReset();
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: { assign } });
  });

  afterEach(() => {
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: originalLocation });
  });

  it('links the Aixle Flow app on JetBrains Marketplace', () => {
    renderModal();

    const link = screen.getByRole('link', { name: 'JetBrains Marketplace' });
    expect(link).toHaveAttribute('href', MARKETPLACE);
    expect(link).toHaveAttribute('target', '_blank');
  });

  it('starts the pairing with the URL entered and sends the browser on to YouTrack', async () => {
    const user = userEvent.setup();
    let sent: unknown;
    answerFetch({
      [`POST ${BASE}/youtrack_connect`]: (init?: RequestInit) => {
        sent = JSON.parse(String(init?.body));
        return { redirect_url: REDIRECT };
      },
    });
    renderModal();

    expect(screen.getByRole('button', { name: 'Continue in YouTrack' })).toBeDisabled();
    await user.type(screen.getByLabelText(/YouTrack URL/), ' https://acme.youtrack.cloud ');
    await user.click(screen.getByRole('button', { name: 'Continue in YouTrack' }));

    await waitFor(() => expect(assign).toHaveBeenCalledWith(REDIRECT));
    expect(sent).toEqual({ instance_url: 'https://acme.youtrack.cloud' });
  });

  it('shows why the server refused the URL and stays on the dialog', async () => {
    const user = userEvent.setup();
    answerFetch({
      [`POST ${BASE}/youtrack_connect`]: jsonResponse(
        { error: 'validation_failed', message: 'Enter the YouTrack URL, for example https://acme.youtrack.cloud' },
        422,
      ),
    });
    renderModal();

    await user.type(screen.getByLabelText(/YouTrack URL/), 'http://acme.youtrack.cloud');
    await user.click(screen.getByRole('button', { name: 'Continue in YouTrack' }));

    expect(
      await screen.findByText('Enter the YouTrack URL, for example https://acme.youtrack.cloud'),
    ).toBeInTheDocument();
    expect(assign).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: 'Continue in YouTrack' })).toBeEnabled();
  });
});
