import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildRunner } from 'test/factories/runner';
import { answerFetch } from 'test/fetchStub';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { AddMachine } from './AddMachine';
import type { RunnerPaths } from './runnerConfig';

const paths: RunnerPaths = {
  list: '/company/settings/runners',
  runner: (id) => `/company/settings/runners/${id}`,
  disable: (id) => `/company/settings/runners/${id}/disable`,
  enable: (id) => `/company/settings/runners/${id}/enable`,
  revoke: (id) => `/company/settings/runners/${id}/revoke`,
  registrationToken: (id) => `/company/settings/runners/${id}/registration_token`,
};

const registration = {
  token: 'arreg_secret-token',
  expiresAt: '2026-11-12T10:00:00Z',
  gatewayUrl: 'https://flow.example.com',
  version: '0.1.0',
  binaries: [
    {
      platform: 'linux-amd64',
      url: 'https://flow.example.com/runner/v1/releases/0.1.0/linux-amd64',
      sha256: 'a'.repeat(64),
    },
    {
      platform: 'linux-arm64',
      url: 'https://flow.example.com/runner/v1/releases/0.1.0/linux-arm64',
      sha256: 'b'.repeat(64),
    },
  ],
};

describe('AddMachine', () => {
  it('mints a token on press and shows the instructions with it, for the chosen platform', async () => {
    const user = userEvent.setup();
    const fetch = answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5, name: 'Build Box' })} paths={paths} />);

    await user.click(screen.getByRole('button', { name: 'Add machine' }));

    const dialog = await screen.findByRole('dialog', { name: 'Add machine' });
    expect(fetch).toHaveBeenCalledTimes(1);
    const script = within(dialog).getByLabelText('Install instructions');
    expect(script).toHaveTextContent(
      "curl -fsSLo aixle-runner 'https://flow.example.com/runner/v1/releases/0.1.0/linux-amd64'",
    );
    // Two spaces between the digest and the file name, as sha256sum -c reads it (toHaveTextContent collapses them).
    expect(script.textContent).toContain(`echo '${'a'.repeat(64)}  aixle-runner' | sha256sum -c -`);
    expect(script).toHaveTextContent(
      "configure --url 'https://flow.example.com' --token 'arreg_secret-token' --name 'build-box-01'",
    );
    expect(script).toHaveTextContent('service install');
    expect(script).toHaveTextContent('sudo ./aixle-runner service start');
    expect(dialog).toHaveTextContent('shown once');

    await user.click(within(dialog).getByText('linux-arm64'));
    expect(script).toHaveTextContent('releases/0.1.0/linux-arm64');
    expect(script).toHaveTextContent('b'.repeat(64));

    await user.click(within(dialog).getByRole('checkbox', { name: /Turn off self-update/ }));
    expect(script).toHaveTextContent('--no-auto-update');
  });

  it('holds back the instructions for a machine name a shell would misread', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5 })} paths={paths} />);

    await user.click(screen.getByRole('button', { name: 'Add machine' }));
    const dialog = await screen.findByRole('dialog', { name: 'Add machine' });
    const name = within(dialog).getByRole('textbox', { name: /Machine name/ });
    await user.clear(name);
    await user.type(name, 'a; rm -rf /');

    expect(within(dialog).getByLabelText('Install instructions')).not.toHaveTextContent('arreg_secret-token');
    expect(within(dialog).getByRole('button', { name: 'Copy' })).toBeDisabled();
  });

  it('forgets the token when closed and mints another on the next press', async () => {
    const user = userEvent.setup();
    let issued = 0;
    const fetch = answerFetch({
      'POST /company/settings/runners/5/registration_token': () => ({ ...registration, token: `arreg_${++issued}` }),
    });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5 })} paths={paths} />);

    await user.click(screen.getByRole('button', { name: 'Add machine' }));
    const dialog = await screen.findByRole('dialog', { name: 'Add machine' });
    expect(dialog).toHaveTextContent('arreg_1');
    await user.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Add machine' })).not.toBeInTheDocument());
    expect(document.body).not.toHaveTextContent('arreg_1');

    await user.click(screen.getByRole('button', { name: 'Add machine' }));
    expect(await screen.findByRole('dialog', { name: 'Add machine' })).toHaveTextContent('arreg_2');
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it('shows the refusal and no dialog when the platform refuses', async () => {
    const user = userEvent.setup();
    answerFetch({
      'POST /company/settings/runners/5/registration_token': new Response(
        JSON.stringify({ error: 'The runner is revoked or deleted.', code: 'runner_revoked' }),
        { status: 409, headers: { 'Content-Type': 'application/json' } },
      ),
    });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5 })} paths={paths} />);

    await user.click(screen.getByRole('button', { name: 'Add machine' }));

    expect(await screen.findByText('The runner is revoked or deleted.')).toBeInTheDocument();
    expect(screen.queryByRole('dialog', { name: 'Add machine' })).not.toBeInTheDocument();
  });
});
