import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { answerFetch } from 'test/fetchStub';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { ArchivedList } from './ArchivedList';

const item = { id: 3, name: 'Old helper', detail: 'old_helper', archivedAt: '2026-09-20T10:00:00Z' };

describe('ArchivedList', () => {
  it('restores an archived agent and reloads the page', async () => {
    const restore = vi.fn<(body: unknown) => object>(() => ({}));
    answerFetch({
      'POST /api/v1/projects/7/entity_versions/restore': (init?: RequestInit) =>
        restore(JSON.parse(String(init?.body))),
    });

    renderPage(<ArchivedList projectId={7} versionableType="Agent" noun="agents" canRestore items={[item]} />);
    await userEvent.click(screen.getByRole('button', { name: 'Restore' }));

    expect(await screen.findByText('Old helper restored')).toBeInTheDocument();
    expect(restore).toHaveBeenCalledWith({ versionable_type: 'Agent', versionable_id: 3, enable_trigger_ids: [] });
    expect(router.reload).toHaveBeenCalled();
  });

  it('asks before switching back on the triggers archiving turned off', async () => {
    const restore = vi.fn<(body: unknown) => object>(() => ({}));
    answerFetch({
      'GET /api/v1/projects/7/entity_versions': {
        versions: [{ id: 9, event: 'archived', disabledTriggerIds: [41, 42] }],
      },
      'POST /api/v1/projects/7/entity_versions/restore': (init?: RequestInit) =>
        restore(JSON.parse(String(init?.body))),
    });

    renderPage(<ArchivedList projectId={7} versionableType="Workflow" noun="workflows" canRestore items={[item]} />);
    await userEvent.click(screen.getByRole('button', { name: 'Restore' }));

    const dialog = await screen.findByRole('dialog', { name: 'Restore workflow' });
    expect(within(dialog).getByText(/switched off 2 triggers/)).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Restore' }));

    expect(restore).toHaveBeenCalledWith({
      versionable_type: 'Workflow',
      versionable_id: 3,
      enable_trigger_ids: [41, 42],
    });
  });

  it('shows the reason a restore was refused', async () => {
    answerFetch({
      'POST /api/v1/projects/7/entity_versions/restore': new Response(
        JSON.stringify({ errors: ['Name already exists in this scope'] }),
        { status: 422 },
      ),
    });

    renderPage(<ArchivedList projectId={7} versionableType="Agent" noun="agents" canRestore items={[item]} />);
    await userEvent.click(screen.getByRole('button', { name: 'Restore' }));

    expect(await screen.findByText('Name already exists in this scope')).toBeInTheDocument();
    expect(router.reload).not.toHaveBeenCalled();
  });

  it('offers only history to a reader who cannot write', () => {
    renderPage(<ArchivedList projectId={7} versionableType="Agent" noun="agents" canRestore={false} items={[item]} />);

    expect(screen.queryByRole('button', { name: 'Restore' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'History of Old helper' })).toBeInTheDocument();
  });

  it('explains the archive when it is empty', () => {
    renderPage(<ArchivedList projectId={7} versionableType="Skill" noun="skills" canRestore items={[]} />);

    expect(screen.getByText('No archived skills')).toBeInTheDocument();
  });
});
