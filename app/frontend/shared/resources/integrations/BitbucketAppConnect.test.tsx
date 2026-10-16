import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { answerFetch, jsonResponse } from 'test/fetchStub';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { BitbucketAppConnect } from './BitbucketAppConnect';

const BASE = '/company/projects/1/integrations';
const INSTALL_URL = 'https://developer.atlassian.com/console/install/app?signature=s&product=bitbucket';

describe('BitbucketAppConnect', () => {
  beforeEach(() => vi.mocked(router.reload).mockClear());

  it('connects a workspace the company already bound and refreshes the page', async () => {
    const user = userEvent.setup();
    const onConnected = vi.fn();
    let sent: unknown;
    answerFetch({
      [`POST ${BASE}/bitbucket_attach`]: (init?: RequestInit) => {
        sent = JSON.parse(String(init?.body));
        return { connected: true, integration_id: 7, name: 'Acme' };
      },
    });
    renderPage(<BitbucketAppConnect basePath={BASE} installUrl={INSTALL_URL} onConnected={onConnected} />);

    await user.type(screen.getByLabelText(/Bitbucket workspace/), 'https://bitbucket.org/acme/');
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await vi.waitFor(() => expect(onConnected).toHaveBeenCalled());
    expect(sent).toEqual({ workspace: 'acme' });
    expect(router.reload).toHaveBeenCalled();
  });

  it('explains the install steps for any other workspace', async () => {
    const user = userEvent.setup();
    answerFetch({ [`POST ${BASE}/bitbucket_attach`]: { install_required: true, install_url: INSTALL_URL } });
    renderPage(<BitbucketAppConnect basePath={BASE} installUrl={INSTALL_URL} />);

    await user.type(screen.getByLabelText(/Bitbucket workspace/), 'globex');
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    const link = await screen.findByRole('link', { name: 'Aixle Flow' });
    expect(link).toHaveAttribute('href', INSTALL_URL);
    expect(link).toHaveAttribute('target', '_blank');
    expect(screen.getByText(/Workspace settings → Aixle Flow and press Connect/)).toBeInTheDocument();
    expect(router.reload).not.toHaveBeenCalled();
  });

  it('says who installs the app when the deployment has no install link', async () => {
    const user = userEvent.setup();
    answerFetch({ [`POST ${BASE}/bitbucket_attach`]: { install_required: true, install_url: null } });
    renderPage(<BitbucketAppConnect basePath={BASE} installUrl={null} />);

    await user.type(screen.getByLabelText(/Bitbucket workspace/), 'globex');
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    expect(await screen.findByText(/ask the people who run it to install Aixle Flow/)).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Aixle Flow' })).not.toBeInTheDocument();
  });

  it('shows why the server refused', async () => {
    const user = userEvent.setup();
    answerFetch({
      [`POST ${BASE}/bitbucket_attach`]: jsonResponse(
        { error: 'permission_denied', message: 'Bitbucket denied this operation' },
        422,
      ),
    });
    renderPage(<BitbucketAppConnect basePath={BASE} installUrl={INSTALL_URL} />);

    await user.type(screen.getByLabelText(/Bitbucket workspace/), 'acme');
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    expect(await screen.findByText('Bitbucket denied this operation')).toBeInTheDocument();
  });

  it('asks for nothing until a workspace is named', () => {
    renderPage(<BitbucketAppConnect basePath={BASE} installUrl={INSTALL_URL} />);

    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });
});
