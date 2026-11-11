import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';
import { answerFetch } from 'test/fetchStub';
import { buildActAsConsent, buildUserConnection } from 'test/factories/userConnection';

import ConnectionsPage from './Connections';

const renderPageWith = ({
  available = true,
  github = buildUserConnection(),
  consents = [buildActAsConsent()],
}: Partial<Parameters<typeof ConnectionsPage>[0]> = {}) =>
  renderAuthedPage(<ConnectionsPage available={available} github={github} consents={consents} />, {
    props: { available, github, consents },
  });

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Profile Connected accounts tab', () => {
  it('offers Connect when no account is connected, and hides the project switches', () => {
    renderPageWith({ github: null });

    expect(screen.getByRole('button', { name: 'Connect GitHub' })).toBeInTheDocument();
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
  });

  it('says so when the installation has not configured the GitHub App', () => {
    renderPageWith({ github: null, available: false });

    expect(screen.queryByRole('button', { name: 'Connect GitHub' })).not.toBeInTheDocument();
    expect(screen.getByText(/has not configured the GitHub App/)).toBeInTheDocument();
  });

  it('shows the connected account with a Disconnect button and two switches per project', () => {
    renderPageWith();

    expect(screen.getByText('Connected')).toBeInTheDocument();
    expect(screen.getByText(/@octo-user/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Disconnect' })).toBeInTheDocument();
    expect(screen.getAllByRole('switch')).toHaveLength(2);
  });

  it('offers Reconnect when the connection needs it', () => {
    renderPageWith({ github: buildUserConnection({ status: 'needs_reconnect' }) });

    expect(screen.getByText('Needs reconnect')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reconnect' })).toBeInTheDocument();
  });

  it('saves a switch with a PATCH and reloads the consents', async () => {
    const fetchSpy = answerFetch({ 'PATCH /profile/act_as_consents': {} });
    renderPageWith();

    await userEvent.click(screen.getByRole('switch', { name: /In my tasks — Acme/ }));

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['consents'] }));
    const [, init] = fetchSpy.mock.calls[0];
    expect(init?.method).toBe('PATCH');
    expect(JSON.parse(String(init?.body))).toEqual({ projectId: 7, provider: 'github', inOwnTasks: true });
  });

  it('asks for confirmation before disconnecting', async () => {
    renderPageWith();

    await userEvent.click(screen.getByRole('button', { name: 'Disconnect' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Disconnect', hidden: false }));

    expect(router.delete).toHaveBeenCalledWith('/profile/connections/github');
  });
});
