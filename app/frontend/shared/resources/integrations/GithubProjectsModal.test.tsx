import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildIntegration } from 'test/factories/integration';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { GithubProjectsModal } from './GithubProjectsModal';

const BASE = '/company/projects/1/integrations';

const PROJECTS = [
  { id: 'PVT_road', number: 5, title: 'Roadmap', url: 'https://github.com/orgs/acme/projects/5', closed: false },
  { id: 'PVT_bugs', number: 7, title: 'Bugs', url: 'https://github.com/orgs/acme/projects/7', closed: false },
];

const mockFetch = (handler: (url: string) => { ok?: boolean; payload: unknown }) =>
  vi.mocked(globalThis.fetch).mockImplementation((async (url: string) => {
    const { ok = true, payload } = handler(String(url));
    return { ok, json: async () => payload } as Response;
  }) as typeof globalThis.fetch);

const githubIntegration = (overrides = {}) =>
  buildIntegration({
    id: 4,
    name: 'acme',
    provider: 'github',
    scopeIndicator: 'project',
    githubAuthMode: 'app',
    githubUrl: 'https://github.com/apps/aixle/installations/12',
    githubProjectsSupported: true,
    githubProjectsPermitted: true,
    ...overrides,
  });

describe('GithubProjectsModal', () => {
  beforeEach(() => vi.mocked(router.patch).mockClear());
  afterEach(() => vi.mocked(globalThis.fetch).mockReset());

  it('starts from the projects the connection covers and saves the new choice', async () => {
    const user = userEvent.setup();
    mockFetch((url) => {
      expect(url).toBe(`${BASE}/4/github_projects`);
      return { payload: { projects: PROJECTS, selected: ['PVT_road'] } };
    });
    renderPage(<GithubProjectsModal integration={githubIntegration()} onClose={() => {}} basePath={BASE} />);

    await user.click(await screen.findByRole('combobox', { name: /GitHub projects/ }));
    await user.click(await screen.findByRole('option', { name: 'Bugs (#7)' }));
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      `${BASE}/4`,
      { githubProjectIds: ['PVT_road', 'PVT_bugs'] },
      expect.anything(),
    );
  });

  it('saves an empty choice, which detaches every GitHub tracker', async () => {
    const user = userEvent.setup();
    mockFetch(() => ({ payload: { projects: PROJECTS, selected: [] } }));
    renderPage(<GithubProjectsModal integration={githubIntegration()} onClose={() => {}} basePath={BASE} />);

    await screen.findByRole('combobox', { name: /GitHub projects/ });
    await user.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(`${BASE}/4`, { githubProjectIds: [] }, expect.anything());
  });

  it('says when an organization owner still has to approve the permissions, and why GitHub refused', async () => {
    mockFetch(() => ({
      ok: false,
      payload: {
        message: 'Resource not accessible by integration. The Aixle GitHub App needs the Projects permission',
      },
    }));
    renderPage(
      <GithubProjectsModal
        integration={githubIntegration({ githubProjectsPermitted: false })}
        onClose={() => {}}
        basePath={BASE}
      />,
    );

    expect(screen.getByText(/has not been granted the Projects and Issues permissions/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'installation settings' })).toHaveAttribute(
      'href',
      'https://github.com/apps/aixle/installations/12',
    );
    expect(await screen.findByText(/Resource not accessible by integration/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled();
  });
});
