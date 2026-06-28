import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import type { Skill } from 'shared/resources/skills/SkillsContent';

import SkillsPage from './SkillsPage';

const skill = (overrides: Partial<Skill> = {}): Skill => ({
  id: 1,
  name: 'react-expert',
  title: null,
  description: 'React best practices',
  package: 'acme@react-expert',
  source: 'acme',
  sourceUrl: 'https://example.com/acme',
  installCount: 1200,
  scopeType: 'project',
  scopeId: 9,
  scopeIndicator: 'project',
  registryUrl: 'https://skills.sh/acme/react-expert',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const pageProps = (skills: Skill[]) => ({
  project: { id: 9, name: 'Falcon Project' },
  skills,
  registryQuery: '',
  registryResults: [],
});

describe('Projects/Skills/SkillsPage', () => {
  it('renders the project skills heading and subtitle', () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    expect(screen.getByText('Project Skills')).toBeInTheDocument();
    expect(screen.getByText('Skills from skills.sh registry installed for this project.')).toBeInTheDocument();
  });

  it('shows the empty state with a registry browse CTA when no skills are installed', () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    expect(screen.getByText('No skills installed')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Browse skills.sh registry' })).toBeInTheDocument();
  });

  it('lists installed skills and filters them by the filter input', async () => {
    renderAuthedPage(<SkillsPage />, {
      props: pageProps([
        skill({ id: 1, name: 'react-expert', package: 'acme@react-expert' }),
        skill({ id: 2, name: 'mantine-guru', package: 'acme@mantine-guru', source: 'acme' }),
      ]),
    });

    expect(screen.getByText('react-expert')).toBeInTheDocument();
    expect(screen.getByText('mantine-guru')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Filter installed skills...'), 'mantine');

    expect(screen.queryByText('react-expert')).not.toBeInTheDocument();
    expect(screen.getByText('mantine-guru')).toBeInTheDocument();
  });

  it('shows the no-match state when the filter matches nothing', async () => {
    renderAuthedPage(<SkillsPage />, {
      props: pageProps([skill({ id: 1, name: 'react-expert' })]),
    });

    await userEvent.type(screen.getByPlaceholderText('Filter installed skills...'), 'zzz');

    expect(screen.getByText('No skills match your filter')).toBeInTheDocument();
  });

  it('opens the registry search modal from the header action', async () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    await userEvent.click(screen.getByRole('button', { name: 'Add from Registry' }));

    expect(screen.getByText('Search skills.sh Registry')).toBeInTheDocument();
    // sanity: opening the modal does not hit the backend on its own
    expect(router.reload).not.toHaveBeenCalled();
  });
});
