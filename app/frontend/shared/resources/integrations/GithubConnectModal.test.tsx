import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { GithubProps } from './GithubConnectModal';
import { GithubConnectModal } from './GithubConnectModal';

const BASE = '/company/projects/1/integrations';

const renderModal = (github: GithubProps = { appConfigured: true }) =>
  renderPage(<GithubConnectModal opened onClose={() => {}} basePath={BASE} github={github} />);

const APP_MODE = /I own the organization/;
const PAT_MODE = /just want to try it/;

describe('GithubConnectModal', () => {
  // window.location is read-only in jsdom; swap it for a plain object so the
  // App path's assignment to location.href can be observed.
  const originalLocation = window.location;

  beforeEach(() => {
    vi.mocked(router.post).mockClear();
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: { href: '' } });
  });

  afterEach(() => {
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: originalLocation });
  });

  it('offers both modes and starts on the recommended app path', () => {
    renderModal();

    expect(screen.getByRole('radio', { name: APP_MODE })).toBeChecked();
    expect(screen.getByRole('radio', { name: PAT_MODE })).not.toBeChecked();
    expect(screen.getByRole('button', { name: 'Continue to GitHub' })).toBeInTheDocument();
  });

  it('sends the app path to the server install endpoint', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('button', { name: 'Continue to GitHub' }));

    expect(window.location.href).toBe(`${BASE}/github_app_install`);
    expect(router.post).not.toHaveBeenCalled();
  });

  it('posts only the token, and the declared mode, on the token path', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));
    await userEvent.type(screen.getByLabelText('Personal access token'), 'ghp_developer_token');
    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        BASE,
        { provider: 'github', authMode: 'pat', personalAccessToken: 'ghp_developer_token' },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  // Switching mode must not carry the other path's credential along, and the
  // App path posts nothing at all.
  it('does not submit a typed token after switching back to the app path', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));
    await userEvent.type(screen.getByLabelText('Personal access token'), 'ghp_developer_token');
    await userEvent.click(screen.getByRole('radio', { name: APP_MODE }));
    await userEvent.click(screen.getByRole('button', { name: 'Continue to GitHub' }));

    expect(router.post).not.toHaveBeenCalled();
    expect(window.location.href).toBe(`${BASE}/github_app_install`);
  });

  it('cannot be submitted with an empty token', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));

    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });

  it('shows the error the server returned without closing', async () => {
    vi.mocked(router.post).mockImplementation(((_url: string, _data: unknown, options: Record<string, unknown>) => {
      (options.onError as (errors: Record<string, string>) => void)({
        personalAccessToken: 'GitHub rejected this token — it is invalid, revoked or expired.',
      });
    }) as unknown as typeof router.post);

    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));
    await userEvent.type(screen.getByLabelText('Personal access token'), 'ghp_revoked');
    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

    expect(await screen.findByText(/invalid, revoked or expired/)).toBeInTheDocument();
    expect(screen.getByLabelText('Personal access token')).toHaveValue('ghp_revoked');
  });

  // On a deployment with no GitHub App the app path can only ever fail, so the
  // dialog opens on the one that works instead of on a dead button.
  it('opens on the token path and disables the app path when no app is configured', () => {
    renderModal({ appConfigured: false });

    expect(screen.getByRole('radio', { name: PAT_MODE })).toBeChecked();
    expect(screen.getByRole('radio', { name: APP_MODE })).toBeDisabled();
    expect(screen.getByLabelText('Personal access token')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Continue to GitHub' })).not.toBeInTheDocument();
  });

  // The scopes are the thing people get wrong, and a grant left out fails one
  // capability rather than the connection — so each one the app actually uses
  // is named, not just the two that cover cloning.
  it('names every scope the app uses and links to GitHub’s token form', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));

    expect(screen.getByText('repo')).toBeInTheDocument();
    expect(screen.getByText('public_repo')).toBeInTheDocument();
    expect(screen.getByText('workflow')).toBeInTheDocument();
    expect(screen.getByText('Metadata')).toBeInTheDocument();
    expect(screen.getAllByText('Contents')).toHaveLength(2);
    expect(screen.getByText('Pull requests')).toBeInTheDocument();
    expect(screen.getByText('Checks')).toBeInTheDocument();
    expect(screen.getByText('Actions')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Create a token on GitHub/ })).toHaveAttribute(
      'href',
      'https://github.com/settings/tokens/new?scopes=repo&description=Aixle%20Flow',
    );
  });

  it('warns that a token acts as its owner and gets no webhooks', async () => {
    renderModal();

    await userEvent.click(screen.getByRole('radio', { name: PAT_MODE }));

    expect(screen.getByText(/This acts as you, not as Aixle/)).toBeInTheDocument();
    expect(screen.getByText(/no webhooks to a token/)).toBeInTheDocument();
  });
});
