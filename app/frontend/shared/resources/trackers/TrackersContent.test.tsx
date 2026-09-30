import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildProjectTracker } from 'test/factories/projectTracker';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { TrackersContent } from './TrackersContent';

const basePath = '/company/projects/7/trackers';
const scopes = [
  { integrationId: 42, integrationName: 'acme/Ops', provider: 'azure_devops', scopes: [{ id: 'p2', name: 'Ops' }] },
];

describe('TrackersContent', () => {
  it('shows each tracker with its handle, role and status', () => {
    renderPage(
      <TrackersContent
        projectId={7}
        trackers={[
          buildProjectTracker(),
          buildProjectTracker({
            id: 6,
            name: 'Legacy',
            handle: 'legacy',
            primary: false,
            access: 'read_only',
            usable: false,
          }),
        ]}
        availableScopes={[]}
        basePath={basePath}
      />,
    );

    const primary = screen.getByRole('row', { name: /^Customer Platform/ });
    expect(within(primary).getByText('customer-platform')).toBeInTheDocument();
    expect(within(primary).getByText('Primary')).toBeInTheDocument();
    expect(within(primary).getByText('Active')).toBeInTheDocument();

    const legacy = screen.getByRole('row', { name: /^Legacy/ });
    expect(within(legacy).getByText('Read-only')).toBeInTheDocument();
    expect(within(legacy).getByText('Connection inactive')).toBeInTheDocument();
  });

  it('makes another tracker primary and toggles read-only through the tracker endpoint', async () => {
    renderPage(
      <TrackersContent
        projectId={7}
        trackers={[
          buildProjectTracker(),
          buildProjectTracker({ id: 6, name: 'Legacy', handle: 'legacy', primary: false }),
        ]}
        availableScopes={[]}
        basePath={basePath}
      />,
    );
    const legacy = screen.getByRole('row', { name: /^Legacy/ });

    await userEvent.click(within(legacy).getByRole('button', { name: 'Make primary' }));
    expect(router.patch).toHaveBeenLastCalledWith(
      `${basePath}/6`,
      { tracker: { primary: true } },
      expect.objectContaining({ preserveScroll: true }),
    );

    await userEvent.click(within(legacy).getByRole('button', { name: 'Make read-only' }));
    expect(router.patch).toHaveBeenLastCalledWith(
      `${basePath}/6`,
      { tracker: { access: 'read_only' } },
      expect.anything(),
    );
  });

  it('detaches only after confirmation, and offers to attach a detached tracker again', async () => {
    renderPage(
      <TrackersContent
        projectId={7}
        trackers={[
          buildProjectTracker(),
          buildProjectTracker({ id: 6, name: 'Legacy', status: 'detached', primary: false }),
        ]}
        availableScopes={[]}
        basePath={basePath}
      />,
    );

    await userEvent.click(
      within(screen.getByRole('row', { name: /^Customer Platform/ })).getByRole('button', { name: 'Detach' }),
    );
    const dialog = await screen.findByRole('dialog', { name: 'Detach tracker' });
    expect(router.delete).not.toHaveBeenCalled();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Detach' }));
    expect(router.delete).toHaveBeenCalledWith(`${basePath}/5`, expect.objectContaining({ preserveScroll: true }));

    await userEvent.click(
      within(screen.getByRole('row', { name: /^Legacy/ })).getByRole('button', { name: 'Attach again' }),
    );
    expect(router.patch).toHaveBeenLastCalledWith(
      `${basePath}/6`,
      { tracker: { status: 'active' } },
      expect.anything(),
    );
  });

  it('offers adding a tracker only when a connection has an unmapped project and the user can write', () => {
    const { unmount } = renderPage(
      <TrackersContent projectId={7} trackers={[]} availableScopes={scopes} basePath={basePath} />,
    );
    expect(screen.getAllByRole('button', { name: 'Add tracker' }).length).toBeGreaterThan(0);
    unmount();

    renderPage(<TrackersContent projectId={7} trackers={[]} availableScopes={[]} basePath={basePath} />);
    expect(screen.queryByRole('button', { name: 'Add tracker' })).not.toBeInTheDocument();
    expect(screen.getByText('No trackers')).toBeInTheDocument();
  });

  it('hides every mutation from a read-only viewer', () => {
    renderPage(
      <TrackersContent projectId={7} trackers={[buildProjectTracker()]} availableScopes={scopes} basePath={basePath} />,
      {
        props: { projectPermissions: { canExecute: false, canManage: false } },
      },
    );

    expect(screen.queryByRole('button', { name: 'Add tracker' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Detach' })).not.toBeInTheDocument();
  });
});
