import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { RegistrySearchModal, SkillsContent, type RegistrySkill, type Skill } from './SkillsContent';

function makeSkill(overrides: Partial<Skill> = {}): Skill {
  return {
    id: 1,
    name: 'eslint-config',
    title: null,
    description: 'Linting rules for the project',
    package: 'acme@eslint-config',
    source: 'acme',
    sourceUrl: 'https://example.com/acme',
    installCount: 0,
    scopeType: null,
    scopeId: null,
    scopeIndicator: 'project',
    registryUrl: 'https://skills.sh/acme/eslint-config',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

function makeRegistrySkill(overrides: Partial<RegistrySkill> = {}): RegistrySkill {
  return {
    id: 'acme/eslint-config',
    slug: 'eslint-config',
    name: 'eslint-config',
    source: 'acme',
    installs: 1200,
    ...overrides,
  };
}

const contentBaseProps = {
  basePath: '/projects/1/skills',
  title: 'Skills',
  subtitle: 'Manage installed skills',
  registryQuery: '',
  registryResults: [] as RegistrySkill[],
};

// Demonstrates asserting that a UI interaction fires the expected BACKEND request.
// The registry search debounces and calls router.reload({ data: { q }, only: [...] }).
// router is mocked (a vi.fn spy) in test/setup.ts, so we assert it was called — without a backend.
describe('RegistrySearchModal — server-side search fires a backend request', () => {
  it('typing a query triggers router.reload with that query', async () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery=""
        results={[]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search skills/i), 'react');

    await waitFor(() =>
      expect(router.reload).toHaveBeenCalledWith(
        expect.objectContaining({ data: { q: 'react' }, only: ['registryQuery', 'registryResults'] }),
      ),
    );
  });

  it('does NOT hit the backend for a single character (min 2 chars)', async () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery=""
        results={[]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search skills/i), 'r');
    // let the 400ms debounce elapse; wrap in act so Mantine's modal state settles cleanly
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 500));
    });

    expect(router.reload).not.toHaveBeenCalled();
  });

  it('clicking Install on a not-installed registry skill fires router.post with the skill id', async () => {
    const skill = makeRegistrySkill({ id: 'acme/router-skill', name: 'router-skill' });
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/9/skills"
        installedPackages={new Set<string>()}
        initialQuery="router"
        results={[skill]}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: /install/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/projects/9/skills',
      { skillId: 'acme/router-skill' },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('renders an "Installed" badge instead of an Install button for already-installed packages', () => {
    const skill = makeRegistrySkill({ source: 'acme', slug: 'eslint-config' });
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>(['acme@eslint-config'])}
        initialQuery="eslint"
        results={[skill]}
      />,
    );

    expect(screen.getByText('Installed')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /install/i })).not.toBeInTheDocument();
  });

  it('sorts results by install count descending', () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery="skill"
        results={[
          makeRegistrySkill({ id: 'a/low', name: 'low-skill', installs: 10 }),
          makeRegistrySkill({ id: 'b/high', name: 'high-skill', installs: 9000 }),
          makeRegistrySkill({ id: 'c/mid', name: 'mid-skill', installs: 500 }),
        ]}
      />,
    );

    const headings = screen.getAllByText(/-skill$/);
    expect(headings.map((h) => h.textContent)).toEqual(['high-skill', 'mid-skill', 'low-skill']);
  });

  it('formats install counts with K and M suffixes', () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery="skill"
        results={[
          makeRegistrySkill({ id: 'a/m', name: 'millions', installs: 2_500_000 }),
          makeRegistrySkill({ id: 'b/k', name: 'thousands', installs: 3400 }),
          makeRegistrySkill({ id: 'c/small', name: 'tiny', installs: 7 }),
        ]}
      />,
    );

    expect(screen.getByText('2.5M installs')).toBeInTheDocument();
    expect(screen.getByText('3.4K installs')).toBeInTheDocument();
    expect(screen.getByText('7 installs')).toBeInTheDocument();
  });

  it('shows the empty-search prompt when there is no initial query', () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery=""
        results={[]}
      />,
    );

    expect(screen.getByText(/registry to find and install agent skills/i)).toBeInTheDocument();
    expect(screen.getByText(/applied automatically at session start/i)).toBeInTheDocument();
  });

  it('shows a no-results message when an initial query yields nothing', () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery="zzznotfound"
        results={[]}
      />,
    );

    expect(screen.getByText(/no skills found for/i)).toBeInTheDocument();
    expect(screen.getByText(/zzznotfound/)).toBeInTheDocument();
  });

  it('clearing the query to empty reloads the registry with an undefined query', async () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery="react"
        results={[]}
      />,
    );

    const input = screen.getByPlaceholderText(/search skills/i);
    await userEvent.clear(input);

    await waitFor(() =>
      expect(router.reload).toHaveBeenCalledWith(
        expect.objectContaining({ data: { q: undefined }, only: ['registryQuery', 'registryResults'] }),
      ),
    );
  });
});

describe('SkillsContent — installed skills grid', () => {
  it('renders the title and subtitle headings', () => {
    renderPage(<SkillsContent {...contentBaseProps} title="My Skills" subtitle="All your skills" skills={[]} />);

    expect(screen.getByText('My Skills')).toBeInTheDocument();
    expect(screen.getByText('All your skills')).toBeInTheDocument();
  });

  it('shows the empty state with a registry CTA when no skills are installed', () => {
    renderPage(<SkillsContent {...contentBaseProps} skills={[]} />);

    expect(screen.getByText('No skills installed')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /browse skills\.sh registry/i })).toBeInTheDocument();
  });

  it('renders one card per installed skill with its name and description', () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        skills={[
          makeSkill({ id: 1, name: 'eslint-config', description: 'Lint everything' }),
          makeSkill({ id: 2, name: 'prettier-config', package: 'acme@prettier', description: 'Format everything' }),
        ]}
      />,
    );

    expect(screen.getByText('eslint-config')).toBeInTheDocument();
    expect(screen.getByText('Lint everything')).toBeInTheDocument();
    expect(screen.getByText('prettier-config')).toBeInTheDocument();
    expect(screen.getByText('Format everything')).toBeInTheDocument();
  });

  it('falls back to "No description available" when description is missing', () => {
    renderPage(<SkillsContent {...contentBaseProps} skills={[makeSkill({ description: null })]} />);

    expect(screen.getByText('No description available')).toBeInTheDocument();
  });

  it('renders the title row when title differs from name but hides it when they match', () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        skills={[
          makeSkill({ id: 1, name: 'alpha-skill', title: 'Alpha Display Title' }),
          makeSkill({ id: 2, name: 'beta-skill', package: 'acme@beta', title: 'beta-skill' }),
        ]}
      />,
    );

    expect(screen.getByText('Alpha Display Title')).toBeInTheDocument();
    // title === name → only the name node should render, not a duplicate title node
    expect(screen.getAllByText('beta-skill')).toHaveLength(1);
  });

  it('filters the installed skills by name as the user types', async () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        skills={[
          makeSkill({ id: 1, name: 'eslint-config', package: 'acme@eslint' }),
          makeSkill({ id: 2, name: 'prettier-config', package: 'acme@prettier' }),
        ]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/filter installed skills/i), 'eslint');

    expect(screen.getByText('eslint-config')).toBeInTheDocument();
    expect(screen.queryByText('prettier-config')).not.toBeInTheDocument();
  });

  it('shows a no-match empty state (without the CTA) when the filter matches nothing', async () => {
    renderPage(<SkillsContent {...contentBaseProps} skills={[makeSkill({ name: 'eslint-config' })]} />);

    await userEvent.type(screen.getByPlaceholderText(/filter installed skills/i), 'nonexistent-term');

    expect(screen.getByText('No skills match your filter')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /browse skills\.sh registry/i })).not.toBeInTheDocument();
  });

  it('opens the registry search modal from the header button', async () => {
    renderPage(<SkillsContent {...contentBaseProps} skills={[makeSkill()]} />);

    await userEvent.click(screen.getByRole('button', { name: /add from registry/i }));

    expect(await screen.findByText('Search skills.sh Registry')).toBeInTheDocument();
  });

  it('opens the delete confirmation modal when the remove icon is clicked on a project skill', async () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        skills={[makeSkill({ name: 'removable-skill', scopeIndicator: 'project' })]}
      />,
    );

    // The card's trash ActionIcon is the only button besides the header "Add from Registry".
    const trashButton = screen.getAllByRole('button').find((b) => !/add from registry/i.test(b.textContent ?? ''));
    expect(trashButton).toBeDefined();
    await userEvent.click(trashButton!);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Delete Skill')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: /^delete$/i })).toBeInTheDocument();
  });

  it('confirming deletion fires router.delete on the skill path', async () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        basePath="/projects/7/skills"
        skills={[makeSkill({ id: 42, name: 'removable-skill', scopeIndicator: 'project' })]}
      />,
    );

    const trashButton = screen.getAllByRole('button').find((b) => !/add from registry/i.test(b.textContent ?? ''));
    await userEvent.click(trashButton!);
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: /^delete$/i }));

    expect(router.delete).toHaveBeenCalledWith(
      '/projects/7/skills/42',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('disables removal of company skills on a project page (no delete handler)', async () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        basePath="/projects/1/skills"
        skills={[makeSkill({ name: 'company-skill', scopeIndicator: 'company' })]}
      />,
    );

    const trashButton = screen.getAllByRole('button').find((b) => !/add from registry/i.test(b.textContent ?? ''));
    // On a project page a company skill's trash icon is disabled; clicking must not open a delete dialog
    expect(trashButton).toBeDisabled();
    await userEvent.click(trashButton!).catch(() => undefined);
    expect(screen.queryByText('Delete Skill')).not.toBeInTheDocument();
  });

  it('renders an enabled remove action for company skills on a non-project page', async () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        basePath="/companies/1/skills"
        skills={[makeSkill({ name: 'company-skill', scopeIndicator: 'company' })]}
      />,
    );

    const trashButton = screen.getAllByRole('button').find((b) => !/add from registry/i.test(b.textContent ?? ''));
    expect(trashButton).not.toBeDisabled();
    await userEvent.click(trashButton!);
    expect(await screen.findByText('Delete Skill')).toBeInTheDocument();
  });

  it('shows formatted install counts on cards and hides them at zero', () => {
    renderPage(
      <SkillsContent
        {...contentBaseProps}
        skills={[
          makeSkill({ id: 1, name: 'popular', package: 'acme@popular', installCount: 5400 }),
          makeSkill({ id: 2, name: 'fresh', package: 'acme@fresh', installCount: 0 }),
        ]}
      />,
    );

    expect(screen.getByText('5.4K installs')).toBeInTheDocument();
    expect(screen.queryByText(/0 installs/)).not.toBeInTheDocument();
  });
});
