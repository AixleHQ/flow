import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildIntegration } from 'test/factories/integration';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { GitlabGroupModal } from './GitlabGroupModal';
import { GitlabTrackersModal } from './GitlabTrackersModal';

const BASE = '/company/projects/1/integrations';

const mockFetch = (handler: (url: string) => unknown) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string) => {
    const payload = handler(String(url));
    return { ok: true, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const gitlabIntegration = (overrides = {}) =>
  buildIntegration({ id: 6, name: 'GitLab · acme', provider: 'gitlab', scopeIndicator: 'project', ...overrides });

describe('GitlabGroupModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());

  it('creates the service account in the one group the person owns', async () => {
    const user = userEvent.setup();
    const integration = gitlabIntegration({
      gitlabAuthMode: 'service_account_pending',
      gitlabGroups: [{ id: '31', fullPath: 'acme', name: 'Acme' }],
    });
    renderPage(<GitlabGroupModal integration={integration} onClose={() => {}} basePath={BASE} />);

    expect(screen.getByText(/keeps only its token/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Create service account' }));

    expect(router.patch).toHaveBeenCalledWith(`${BASE}/6`, { gitlabGroupId: '31' }, expect.anything());
  });

  it('waits for a pick when the person owns several groups', () => {
    const integration = gitlabIntegration({
      gitlabAuthMode: 'service_account_pending',
      gitlabGroups: [
        { id: '31', fullPath: 'acme', name: 'Acme' },
        { id: '32', fullPath: 'acme/ops', name: 'Ops' },
      ],
    });
    renderPage(<GitlabGroupModal integration={integration} onClose={() => {}} basePath={BASE} />);

    expect(screen.getByRole('button', { name: 'Create service account' })).toBeDisabled();
  });
});

describe('GitlabTrackersModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('picks a project, takes its first board, and saves both', async () => {
    const user = userEvent.setup();
    mockFetch((url) => {
      if (url.endsWith('/gitlab_projects'))
        return { projects: [{ id: '501', path: 'acme/app', name: 'Acme / App' }], selected: [] };
      expect(url).toBe(`${BASE}/6/gitlab_boards?gitlab_project_id=501`);
      return { boards: [{ id: '71', name: 'Development', lists: ['Ready for AI', 'Doing'] }] };
    });
    renderPage(<GitlabTrackersModal integration={gitlabIntegration()} onClose={() => {}} basePath={BASE} />);

    await user.click(await screen.findByRole('combobox', { name: /GitLab projects/ }));
    await user.click(await screen.findByRole('option', { name: 'acme/app' }));
    expect(await screen.findByDisplayValue('Development — Ready for AI, Doing')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      `${BASE}/6`,
      { gitlabTrackers: [{ projectId: '501', boardId: '71' }] },
      expect.anything(),
    );
  });
});
