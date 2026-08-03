import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import type { CatalogSkill, Skill } from 'shared/resources/skills/SkillsContent';

import SkillsPage from './SkillsPage';

const skill = (overrides: Partial<Skill> = {}): Skill => ({
  id: 1,
  name: 'react-expert',
  title: null,
  description: 'React best practices',
  package: 'acme/skills@react-expert',
  source: 'acme/skills',
  sourceUrl: 'https://github.com/acme/skills',
  installCount: 1200,
  origin: 'registry',
  scopeType: 'Project',
  scopeId: 9,
  scopeIndicator: 'project',
  registryUrl: 'https://skills.sh/acme/skills/react-expert',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const catalogSkill = (overrides: Partial<CatalogSkill> = {}): CatalogSkill => ({
  registryId: 'anthropics/skills/frontend-design',
  source: 'anthropics/skills',
  slug: 'frontend-design',
  title: null,
  description: 'Design guidance for frontend work',
  installs: 734_415,
  featured: true,
  pickerName: 'frontend-design',
  package: 'anthropics/skills@frontend-design',
  iconUrl: null,
  registryUrl: 'https://skills.sh/anthropics/skills/frontend-design',
  auditRisk: null,
  auditProviders: [],
  ...overrides,
});

const pageProps = (skills: Skill[], catalogSkills: CatalogSkill[] = []) => ({
  project: { id: 9, name: 'Falcon Project' },
  skills,
  catalogQuery: '',
  catalogSkills,
  catalogSyncedAt: null,
});

describe('Projects/Skills/SkillsPage', () => {
  it('renders the project skills heading and subtitle', () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    expect(screen.getByText('Project Skills')).toBeInTheDocument();
    expect(
      screen.getByText('Skills this project can use — installed from the public catalog or written by hand.'),
    ).toBeInTheDocument();
  });

  it('lists installed skills with their install counts', () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([skill()]) });

    expect(screen.getByText('react-expert')).toBeInTheDocument();
    expect(screen.getByText('1.2K installs')).toBeInTheDocument();
  });

  it('shows the empty state when nothing is installed', () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    expect(screen.getByText('No skills installed')).toBeInTheDocument();
  });

  // The defect this feature exists to fix: the catalog now has something to show
  // before anyone types a query.
  it('opens the catalog on server-provided entries without a search', async () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([], [catalogSkill()]) });

    // The header and the empty state both offer it; either entry point will do.
    await userEvent.click(screen.getAllByRole('button', { name: 'Browse catalog' })[0]);

    expect(screen.getByText('Suggested skills')).toBeInTheDocument();
    expect(screen.getByText('frontend-design')).toBeInTheDocument();
    // Opening the catalog costs nothing: the props are already on the page.
    expect(router.get).not.toHaveBeenCalled();
  });

  it('opens the manual authoring form from the header', async () => {
    renderAuthedPage(<SkillsPage />, { props: pageProps([]) });

    await userEvent.click(screen.getAllByRole('button', { name: 'Add manually' })[0]);

    expect(screen.getByLabelText('SKILL.md content')).toBeInTheDocument();
  });
});
