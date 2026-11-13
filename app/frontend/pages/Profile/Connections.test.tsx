import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildActAsConsent, buildUserConnection } from 'test/factories/userConnection';
import { answerFetch } from 'test/fetchStub';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import ConnectionsPage from './Connections';

type PageProps = Parameters<typeof ConnectionsPage>[0];

const renderPageWith = ({
  available = { github: true, gitlab: true },
  github = buildUserConnection(),
  gitlab = null,
  consents = {},
}: {
  available?: PageProps['available'];
  github?: PageProps['connections']['github'];
  gitlab?: PageProps['connections']['gitlab'];
  consents?: Partial<PageProps['consents']>;
} = {}) => {
  const props: PageProps = {
    available,
    connections: { github, gitlab },
    consents: { github: [buildActAsConsent()], gitlab: [buildActAsConsent({ provider: 'gitlab' })], ...consents },
  };
  return renderAuthedPage(<ConnectionsPage {...props} />, { props });
};

afterEach, describe, expect, it, vi } from 'vitest';

import { buildActAsConsent, buildUserConnection } from 'test/factories/userConnection';
import { answerFetch } from 'test/fetchStub';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

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

  it('offers GitLab next to GitHub, and says so when GitLab is not configured', () => {
    renderPageWith({ github: null, available: { github: true, gitlab: false } });

    expect(screen.getByRole('button', { name: 'Connect GitHub' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Connect GitLab' })).not.toBeInTheDocument();
    expect(screen.getByText(/has not configured GitLab/)).toBeInTheDocument();
  });

  it('shows a connected GitLab account with its own switches', () => {
    renderPageWith({
      github: null,
      gitlab: buildUserConnection({ provider: 'gitlab', login: 'lab-user', name: 'Lab User' }),
    });

    expect(screen.getByText(/@lab-user/)).toBeInTheDocument();
    expect(screen.getByText('What agents may do as you on GitLab')).toBeInTheDocument();
    expect(screen.getAllByRole('switch')).toHaveLength(2);
  });

  it('saves a GitLab switch against the gitlab provider', async () => {
    const fetchSpy = answerFetch({ 'PATCH /profile/connections/gitlab/act_as_consents/7': {} });
    renderPageWith({ github: null, gitlab: buildUserConnection({ provider: 'gitlab' }) });

    await userEvent.click(screen.getByRole('switch', { name: /In tasks that aren't mine — Acme/ }));

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['consents'] }));
    expect(JSON.parse(String(fetchSpy.mock.calls[0][1]?.body))).toEqual({ inOthersTasks: true });
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
    const fetchSpy = answerFetch({ 'PATCH /profile/connections/github/act_as_consents/7': {} });
    renderPageWith();

    await userEvent.click(screen.getByRole('switch', { name: /In my tasks — Acme/ }));

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['consents'] }));
    const [, init] = fetchSpy.mock.calls[0];
    expect(init?.method).toBe('PATCH');
    expect(JSON.parse(String(init?.body))).toEqual({ inOwnTasks: true });
  });

  it('asks for confirmation before disconnecting', async () => {
    renderPageWith();

    await userEvent.click(screen.getByRole('button', { name: 'Disconnect' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Disconnect' }));

    expect(router.delete).toHaveBeenCalledWith('/profile/connections/github');
  });
});
