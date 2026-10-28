import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildRunner, buildRunnerTypeOption } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import RunnerPage from './RunnerPage';

const project = { id: 7, name: 'Aixle Core' };

const render = (props: Record<string, unknown> = {}) =>
  renderAuthedPage(<RunnerPage />, {
    props: {
      project,
      runner: buildRunner({ id: 2, name: 'project-box', scope: 'project', projectId: 7 }),
      runnerTypes: [buildRunnerTypeOption()],
      canManage: true,
      projectPermissions: { canExecute: true, canManage: true, canManageCompany: false },
      features: { externalRunners: true },
      ...props,
    },
  });

describe('Projects/Runners/RunnerPage', () => {
  it('manages a project runner through the project routes', async () => {
    const user = userEvent.setup();
    render();

    expect(screen.getByRole('link', { name: 'Runners' })).toHaveAttribute('href', '/company/projects/7/runners');
    await user.click(screen.getByRole('button', { name: 'Disable' }));
    expect(router.post).toHaveBeenCalledWith('/company/projects/7/runners/2/disable', {}, expect.anything());
  });

  it('shows a company runner read-only, pointing an admin to company settings', () => {
    render({
      runner: buildRunner({ id: 1, name: 'company-box', scope: 'company' }),
      canManage: false,
      projectPermissions: { canExecute: true, canManage: true, canManageCompany: true },
    });

    expect(screen.getByText(/A company runner/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Manage it there' })).toHaveAttribute(
      'href',
      '/company/settings/runners/1',
    );
    ['Edit', 'Disable', 'Revoke', 'Delete'].forEach((name) =>
      expect(screen.queryByRole('button', { name })).not.toBeInTheDocument(),
    );
  });

  it('renders nothing with the flag off', () => {
    render({ features: { externalRunners: false } });

    expect(screen.queryByRole('heading', { name: 'project-box' })).not.toBeInTheDocument();
  });
});
