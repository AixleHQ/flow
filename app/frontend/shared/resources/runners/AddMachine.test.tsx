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
  returnToService: (id, machineId) => `/company/settings/runners/${id}/machines/${machineId}/return_to_service`,
  revokeMachine: (id, machineId) => `/company/settings/runners/${id}/machines/${machineId}/revoke`,
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

const open = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(screen.getByRole('button', { name: 'Add machine' }));
  return screen.findByRole('dialog', { name: 'Add machine' });
};

describe('AddMachine', () => {
  it('mints a token on press and opens on Docker with the one default command', async () => {
    const user = userEvent.setup();
    const fetch = answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5, name: 'Build Box' })} paths={paths} />);

    const dialog = await open(user);

    expect(fetch).toHaveBeenCalledTimes(1);
    expect(within(dialog).getByRole('radio', { name: 'Docker' })).toBeChecked();
    expect(within(dialog).getByLabelText('Install instructions').textContent).toBe(
      "docker run --rm --name aixle-runner -v /var/run/docker.sock:/var/run/docker.sock -e AIXLE_RUNNER_URL='https://flow.example.com' -e AIXLE_RUNNER_TOKEN='arreg_secret-token' -e AIXLE_RUNNER_NAME='build-box-01' 'ghcr.io/aixlehq/aixle-runner:0.1.0'",
    );
    expect(dialog).toHaveTextContent('shown once');
    expect(dialog).toHaveTextContent('Needs Docker 26 or later.');
    expect(dialog).toHaveTextContent('put sudo in front');
    for (const label of [/private registry/, /Keep the registration in a volume/, /Keep it in a directory/]) {
      expect(within(dialog).getByRole('checkbox', { name: label })).not.toBeChecked();
    }
  });

  it('adds the private registry mount, and each keep box adds its own flags and clears the other', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5, name: 'Build Box' })} paths={paths} />);
    const dialog = await open(user);
    const command = () => within(dialog).getByLabelText('Install instructions').textContent ?? '';

    await user.click(within(dialog).getByRole('checkbox', { name: /private registry/ }));
    expect(command()).toContain('-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"');
    expect(command()).toContain('docker run --rm');

    const volume = within(dialog).getByRole('checkbox', { name: /Keep the registration in a volume/ });
    const directory = within(dialog).getByRole('checkbox', { name: /Keep it in a directory/ });
    await user.click(volume);
    expect(command()).toContain('docker run -d --restart unless-stopped');
    expect(command()).toContain('-v aixle-runner:/var/lib/aixle-runner');
    expect(command()).toContain('-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0');
    expect(command()).not.toContain('--rm');

    await user.click(directory);
    expect(volume).not.toBeChecked();
    expect(command()).not.toContain('-v aixle-runner:');
    const path = within(dialog).getByRole('textbox', { name: /Directory on this machine/ });
    await user.clear(path);
    await user.type(path, '/srv/runner');
    expect(command()).toContain("-v '/srv/runner:/var/lib/aixle-runner'");
    expect(command()).toContain('-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0');

    await user.clear(path);
    await user.type(path, 'relative');
    expect(command()).toBe('Enter a valid machine name to see the instructions.');
    expect(within(dialog).getByRole('button', { name: 'Copy' })).toBeDisabled();

    await user.clear(path);
    await user.type(path, '/data:ro');
    expect(command()).toBe('Enter a valid machine name to see the instructions.');
    expect(within(dialog).getByText(/without a colon/)).toBeInTheDocument();

    await user.click(directory);
    expect(command()).toContain('docker run --rm');
    expect(within(dialog).queryByRole('textbox', { name: /Directory on this machine/ })).not.toBeInTheDocument();
  });

  it('gives one command on the Linux service tab, with self-update off on request', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5, name: 'Build Box' })} paths={paths} />);
    const dialog = await open(user);

    await user.click(within(dialog).getByText('Linux service'));

    const command = within(dialog).getByLabelText('Install instructions');
    expect(command.textContent).toBe(
      "curl -fsSL 'https://flow.example.com/runner/v1/machine-install.sh' | sudo sh -s -- --token 'arreg_secret-token' --name 'build-box-01'",
    );
    expect(within(dialog).queryByRole('checkbox', { name: /private registry/ })).not.toBeInTheDocument();
    await user.click(within(dialog).getByRole('checkbox', { name: /Turn off self-update/ }));
    expect(command.textContent).toMatch(/--name 'build-box-01' --no-auto-update$/);
  });

  it('keeps the removal and step-by-step sections collapsed until opened', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5, name: 'Build Box' })} paths={paths} />);
    const dialog = await open(user);

    expect(within(dialog).queryByText('Install step by step')).not.toBeInTheDocument();
    expect(within(dialog).queryByLabelText('Remove instructions')).not.toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: 'Remove this machine' }));
    expect(dialog).toHaveTextContent('docker stop aixle-runner');
    expect(dialog.textContent).not.toContain('--user');

    await user.click(within(dialog).getByRole('checkbox', { name: /Keep the registration in a volume/ }));
    expect(within(dialog).getByLabelText('Remove instructions').textContent).toContain('docker volume rm aixle-runner');
    expect(within(dialog).getByLabelText('Remove instructions').textContent).not.toContain('--user');

    await user.click(within(dialog).getByRole('checkbox', { name: /Keep it in a directory/ }));
    expect(within(dialog).getByLabelText('Remove instructions').textContent).toContain('docker rm -f aixle-runner');
    expect(within(dialog).getByLabelText('Remove instructions').textContent).not.toContain('rm -rf');

    await user.click(within(dialog).getByText('Linux service'));
    expect(within(dialog).getByLabelText('Remove instructions').textContent).toContain('service uninstall');
    expect(within(dialog).queryByLabelText('Step-by-step instructions')).not.toBeInTheDocument();
    await user.click(within(dialog).getByRole('button', { name: 'Install step by step' }));
    const steps = within(dialog).getByLabelText('Step-by-step instructions');
    expect(steps).toHaveTextContent(
      "curl -fsSLo aixle-runner 'https://flow.example.com/runner/v1/releases/0.1.0/linux-amd64'",
    );
    expect(steps.textContent).toContain(`echo '${'a'.repeat(64)}  aixle-runner' | sha256sum -c -`);
    await user.click(within(dialog).getByText('linux-arm64'));
    expect(steps).toHaveTextContent('releases/0.1.0/linux-arm64');
    expect(steps).toHaveTextContent('b'.repeat(64));
  });

  it('holds back the instructions for a machine name a shell would misread', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5 })} paths={paths} />);

    const dialog = await open(user);
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

  it('resets the tab and the boxes when the dialog is opened again', async () => {
    const user = userEvent.setup();
    answerFetch({ 'POST /company/settings/runners/5/registration_token': registration });
    renderAuthedPage(<AddMachine runner={buildRunner({ id: 5 })} paths={paths} />);

    let dialog = await open(user);
    await user.click(within(dialog).getByRole('checkbox', { name: /Keep the registration in a volume/ }));
    await user.click(within(dialog).getByText('Linux service'));
    await user.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Add machine' })).not.toBeInTheDocument());

    dialog = await open(user);
    expect(within(dialog).getByRole('radio', { name: 'Docker' })).toBeChecked();
    expect(within(dialog).getByRole('checkbox', { name: /Keep the registration in a volume/ })).not.toBeChecked();
  });
});
