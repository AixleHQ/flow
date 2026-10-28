import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { buildRunner, buildRunnerTypeOption } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { RunnerPaths } from './runnerConfig';
import { RunnerFormModal } from './RunnerFormModal';

const paths: RunnerPaths = {
  list: '/company/settings/runners',
  runner: (id) => `/company/settings/runners/${id}`,
  disable: (id) => `/company/settings/runners/${id}/disable`,
  enable: (id) => `/company/settings/runners/${id}/enable`,
  revoke: (id) => `/company/settings/runners/${id}/revoke`,
};

const renderForm = (runner?: ReturnType<typeof buildRunner>) =>
  renderAuthedPage(
    <RunnerFormModal opened onClose={vi.fn()} runnerTypes={[buildRunnerTypeOption()]} paths={paths} runner={runner} />,
  );

async function pickManual(user: ReturnType<typeof userEvent.setup>) {
  const dialog = await screen.findByRole('dialog', { name: 'New runner' });
  await user.click(within(dialog).getByRole('radio', { name: 'Manual' }));
  await user.click(within(dialog).getByRole('button', { name: 'Next' }));
  return dialog;
}

async function fillLimits(user: ReturnType<typeof userEvent.setup>, dialog: HTMLElement, name = 'gpu-box') {
  await user.click(within(dialog).getByRole('button', { name: 'Next' }));
  await user.type(within(dialog).getByRole('textbox', { name: /^Name/ }), name);
}

const sentRunner = () => (vi.mocked(router.post).mock.calls.at(-1)?.[1] as { runner: Record<string, unknown> }).runner;

describe('RunnerFormModal', () => {
  it('starts from the type cards and renders the manual schema with its defaults, mounts first', async () => {
    const user = userEvent.setup();
    renderForm();

    const dialog = await screen.findByRole('dialog', { name: 'New runner' });
    expect(within(dialog).getByRole('button', { name: 'Next' })).toBeDisabled();
    await pickManual(user);

    const fieldset = within(dialog).getByRole('group', { name: 'Give the agent your toolchain' });
    expect(within(fieldset).getByText('Extra mounts')).toBeInTheDocument();
    expect(within(fieldset).getByRole('switch', { name: /^Home directory mount/ })).not.toBeChecked();
    expect(within(fieldset).getByRole('switch', { name: /^Keep a workspace volume/ })).toBeChecked();
    expect(within(fieldset).getByRole('radio', { name: 'bridge (default)' })).toBeChecked();
    expect(within(fieldset).getByRole('radio', { name: 'private (default)' })).toBeChecked();
    expect(within(dialog).getByRole('switch', { name: /^Auto-update/ })).toBeChecked();
    expect(within(dialog).getByRole('textbox', { name: /Reconnect grace/ })).toHaveAttribute('placeholder', '900');
    expect(within(dialog).getByText('Default: 900.')).toBeInTheDocument();
    expect(within(dialog).getByRole('radio', { name: /Reuse \(default\)/ })).toBeChecked();
    expect(
      within(dialog).getByText(/Fresh on a manual runner wipes everything Aixle put on the machine/),
    ).toBeInTheDocument();
  });

  it('sends only the keys the user set, with their §2.7 names', async () => {
    const user = userEvent.setup();
    renderForm();
    const dialog = await pickManual(user);

    const network = within(dialog).getByRole('radiogroup', { name: 'Network' });
    await user.click(within(network).getByRole('radio', { name: 'host' }));
    await user.click(within(dialog).getByRole('switch', { name: /^Auto-update/ }));
    expect(within(dialog).getByRole('button', { name: 'Use the default for Network' })).toBeInTheDocument();

    await fillLimits(user, dialog);
    const concurrency = within(dialog).getByRole('textbox', { name: /Max concurrency/ });
    await user.clear(concurrency);
    await user.type(concurrency, '3');
    await user.click(within(dialog).getByRole('button', { name: 'Create runner' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/settings/runners',
      {
        runner: {
          name: 'gpu-box',
          runner_type: 'manual',
          max_concurrency: 3,
          max_environments: null,
          config: { container: { network: 'host' }, auto_update: false },
        },
      },
      expect.objectContaining({ preserveState: true }),
    );
  });

  it('asks for an acknowledgement of each writable host mount and sends it by target', async () => {
    const user = userEvent.setup();
    renderForm();
    const dialog = await pickManual(user);

    await user.click(within(dialog).getByRole('button', { name: 'Add to Extra mounts' }));
    await user.type(within(dialog).getByRole('textbox', { name: 'Extra mounts 1: Source' }), '/srv/data');
    await user.type(within(dialog).getByRole('textbox', { name: 'Extra mounts 1: Target' }), '/data');
    await user.click(within(dialog).getByRole('checkbox', { name: 'Extra mounts 1: Writable' }));

    const acknowledgement = within(dialog).getByRole('checkbox', {
      name: 'I understand the agent can write to /data on this machine',
    });
    expect(acknowledgement).not.toBeChecked();

    await fillLimits(user, dialog);
    await user.click(within(dialog).getByRole('button', { name: 'Create runner' }));

    expect(router.post).not.toHaveBeenCalled();
    expect(await within(dialog).findByText('Acknowledge every writable host mount: /data')).toBeInTheDocument();

    await user.click(
      within(dialog).getByRole('checkbox', { name: 'I understand the agent can write to /data on this machine' }),
    );
    await user.click(within(dialog).getByRole('button', { name: 'Next' }));
    await user.click(within(dialog).getByRole('button', { name: 'Create runner' }));

    expect(sentRunner().config).toEqual({
      container: {
        extra_mounts: [{ source: '/srv/data', target: '/data', writable: true }],
        acknowledged_writable_mounts: ['/data'],
      },
    });
  });

  it('offers the Docker socket only with privileged mounts allowed, and warns about it', async () => {
    const user = userEvent.setup();
    renderForm();
    const dialog = await pickManual(user);

    const socket = () => within(dialog).getByRole('switch', { name: /^Mount the Docker socket/ });
    expect(socket()).toBeDisabled();

    await user.click(within(dialog).getByRole('switch', { name: /^Allow privileged mounts/ }));
    expect(socket()).toBeEnabled();
    await user.click(socket());
    expect(within(dialog).getByText(/gives the agent root on this machine/)).toBeInTheDocument();

    await user.click(within(dialog).getByRole('switch', { name: /^Allow privileged mounts/ }));
    expect(socket()).not.toBeChecked();
    expect(socket()).toBeDisabled();
  });

  it('shows the server’s errors at their fields, and the rest above the form', async () => {
    vi.mocked(router.post).mockImplementationOnce((...args: unknown[]) => {
      const options = args[2] as { onError?: (errors: Record<string, unknown>) => void };
      options.onError?.({
        name: ['has already been taken'],
        maxConcurrency: ['must be greater than 0'],
        config: [
          'container.network must be one of bridge, host',
          'ephemeral is not a config key: it is set per machine at registration',
        ],
      });
    });
    const user = userEvent.setup();
    renderForm();
    const dialog = await pickManual(user);
    await fillLimits(user, dialog);
    await user.click(within(dialog).getByRole('button', { name: 'Create runner' }));

    // The first step with an error is the configuration.
    expect(await within(dialog).findByText('container.network must be one of bridge, host')).toBeInTheDocument();
    expect(
      within(dialog).getByText('ephemeral is not a config key: it is set per machine at registration'),
    ).toBeInTheDocument();

    await user.click(within(dialog).getByRole('button', { name: 'Next' }));
    expect(within(dialog).getByText('has already been taken')).toBeInTheDocument();
    expect(within(dialog).getByText('must be greater than 0')).toBeInTheDocument();
  });

  it('edits a runner without the type step, keeping its config and never sending its type', async () => {
    const user = userEvent.setup();
    const runner = buildRunner({ id: 4, name: 'build-box', reusePolicy: 'fresh', config: { auto_update: false } });
    renderForm(runner);

    const dialog = await screen.findByRole('dialog', { name: 'Edit build-box' });
    expect(within(dialog).queryByRole('radio', { name: 'Manual' })).not.toBeInTheDocument();
    expect(within(dialog).getByRole('switch', { name: /^Auto-update/ })).not.toBeChecked();

    await user.click(within(dialog).getByRole('button', { name: 'Next' }));
    await user.click(within(dialog).getByRole('button', { name: 'Save runner' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/settings/runners/4',
      {
        runner: {
          name: 'build-box',
          max_concurrency: 2,
          max_environments: null,
          reuse_policy: 'fresh',
          config: { auto_update: false },
        },
      },
      expect.anything(),
    );
  });
});
