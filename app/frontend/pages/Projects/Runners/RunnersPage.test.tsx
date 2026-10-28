import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildRunner, buildRunnerTypeOption } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import RunnersPage from './RunnersPage';

const project = { id: 7, name: 'Aixle Core' };
const runners = [
  buildRunner({ id: 1, name: 'company-box', scope: 'company' }),
  buildRunner({ id: 2, name: 'project-box', scope: 'project', projectId: 7, status: 'connected' }),
];

const render = (props: Record<string, unknown> = {}) =>
  renderAuthedPage(<RunnersPage />, {
    props: {
      project,
      runners,
      runnerTypes: [buildRunnerTypeOption()],
      canManage: true,
      projectPermissions: { canExecute: true, canManage: true, canManageCompany: false },
      features: { externalRunners: true },
      ...props,
    },
  });

describe('Projects/Runners/RunnersPage', () => {
  it('splits the company’s runners from the project’s own, both linking to the project runner page', () => {
    render();

    const company = screen.getByRole('region', { name: 'From your company' });
    expect(within(company).getByRole('link', { name: 'company-box' })).toHaveAttribute(
      'href',
      '/company/projects/7/runners/1',
    );
    expect(within(company).queryByText('project-box')).not.toBeInTheDocument();

    const own = screen.getByRole('region', { name: 'This project' });
    expect(within(own).getByRole('link', { name: 'project-box' })).toHaveAttribute(
      'href',
      '/company/projects/7/runners/2',
    );
    expect(within(own).getByText('Connected')).toBeInTheDocument();
  });

  it('links a company admin to the company settings page', () => {
    const { unmount } = render();
    expect(screen.queryByRole('link', { name: 'Manage in company settings' })).not.toBeInTheDocument();
    unmount();

    render({ projectPermissions: { canExecute: true, canManage: true, canManageCompany: true } });
    expect(screen.getByRole('link', { name: 'Manage in company settings' })).toHaveAttribute(
      'href',
      '/company/settings/runners',
    );
  });

  it('creates a project runner from New runner, and hides it without canManage', async () => {
    const user = userEvent.setup();
    const { unmount } = render();

    await user.click(screen.getByRole('button', { name: 'New runner' }));
    expect(await screen.findByRole('dialog', { name: 'New runner' })).toBeInTheDocument();
    unmount();

    render({ canManage: false });
    expect(screen.queryByRole('button', { name: 'New runner' })).not.toBeInTheDocument();
  });

  it('renders nothing with the flag off', () => {
    render({ features: { externalRunners: false } });

    expect(screen.queryByRole('heading', { name: 'Runners' })).not.toBeInTheDocument();
    expect(screen.queryByText('company-box')).not.toBeInTheDocument();
  });
});
