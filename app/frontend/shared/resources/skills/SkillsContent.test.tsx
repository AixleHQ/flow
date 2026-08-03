import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { SkillsContent, type CatalogSkill, type Skill } from './SkillsContent';

function makeSkill(overrides: Partial<Skill> = {}): Skill {
  return {
    id: 1,
    name: 'eslint-config',
    title: null,
    description: 'Linting rules for the project',
    package: 'acme/skills@eslint-config',
    source: 'acme/skills',
    sourceUrl: 'https://github.com/acme/skills',
    installCount: 0,
    origin: 'registry',
    content: null,
    scopeType: 'Project',
    scopeId: 1,
    scopeIndicator: 'project',
    registryUrl: 'https://skills.sh/acme/skills/eslint-config',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

function makeCatalogSkill(overrides: Partial<CatalogSkill> = {}): CatalogSkill {
  return {
    registryId: 'anthropics/skills/pdf',
    source: 'anthropics/skills',
    slug: 'pdf',
    title: null,
    description: 'Fill PDF forms',
    installs: 1200,
    featured: true,
    pickerName: 'pdf',
    package: 'anthropics/skills@pdf',
    iconUrl: null,
    registryUrl: 'https://skills.sh/anthropics/skills/pdf',
    auditRisk: null,
    auditProviders: [],
    ...overrides,
  };
}

const baseProps = {
  basePath: '/company/projects/1/skills',
  title: 'Project Skills',
  subtitle: 'Skills this project can use',
  catalogSkills: [] as CatalogSkill[],
  catalogQuery: '',
  catalogSyncedAt: null,
};

describe('SkillsContent — installed skills', () => {
  it('lists installed skills and filters them', async () => {
    renderPage(
      <SkillsContent
        {...baseProps}
        skills={[
          makeSkill({ id: 1, name: 'eslint-config' }),
          makeSkill({ id: 2, name: 'mantine-guru', package: 'acme/skills@mantine-guru' }),
        ]}
      />,
    );

    expect(screen.getByText('eslint-config')).toBeInTheDocument();
    expect(screen.getByText('mantine-guru')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Filter installed skills...'), 'mantine');

    expect(screen.queryByText('eslint-config')).not.toBeInTheDocument();
    expect(screen.getByText('mantine-guru')).toBeInTheDocument();
  });

  // A hand-written skill has no registry page to link to, so the card says where it
  // came from instead of pointing at a URL that would 404.
  it('labels a hand-written skill and omits the registry link', () => {
    renderPage(
      <SkillsContent
        {...baseProps}
        skills={[makeSkill({ origin: 'manual', source: null, package: null, registryUrl: null })]}
      />,
    );

    expect(screen.getByText('manual')).toBeInTheDocument();
    expect(screen.getByText('written here')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /eslint-config on skills.sh/i })).not.toBeInTheDocument();
  });

  it('falls back to a placeholder when a skill has no description', () => {
    renderPage(<SkillsContent {...baseProps} skills={[makeSkill({ description: null })]} />);

    expect(screen.getByText('No description available')).toBeInTheDocument();
  });

  // The card heading already IS the name; printing an identical title under it just
  // wastes the row.
  it('does not repeat a title that equals the name', () => {
    renderPage(<SkillsContent {...baseProps} skills={[makeSkill({ title: 'eslint-config' })]} />);

    expect(screen.getAllByText('eslint-config')).toHaveLength(1);
  });

  // The trash icon → confirmation → router.delete chain is the only destructive path
  // on this page, and it is wired here rather than in the modal.
  it('opens the delete confirmation from the card and deletes on confirm', async () => {
    renderPage(<SkillsContent {...baseProps} skills={[makeSkill({ id: 7 })]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Remove eslint-config' }));
    expect(screen.getByText('Delete Skill')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/1/skills/7',
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  // Editing reuses the authoring form — a skill IS a SKILL.md, so there is one editor.
  it('opens the editor on a hand-written skill with its file loaded', async () => {
    const content = '---\nname: house-style\ndescription: Our conventions\n---\n\n# House style\n';
    renderPage(
      <SkillsContent
        {...baseProps}
        skills={[makeSkill({ id: 4, name: 'house-style', origin: 'manual', source: null, package: null, content })]}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Edit house-style' }));

    const textarea = screen.getByLabelText('SKILL.md content') as HTMLTextAreaElement;
    expect(textarea.value).toBe(content);
    expect(screen.getByRole('button', { name: 'Save changes' })).toBeInTheDocument();
  });

  // A registry skill's content belongs to the source it names, and the next install
  // would clobber an edit — so there is no edit affordance at all.
  it('offers no editor for a registry skill', () => {
    renderPage(<SkillsContent {...baseProps} skills={[makeSkill({ name: 'eslint-config' })]} />);

    expect(screen.queryByRole('button', { name: 'Edit eslint-config' })).not.toBeInTheDocument();
  });

  it('saving an edit patches the skill', async () => {
    const content = '---\nname: house-style\ndescription: Our conventions\n---\n\nbody\n';
    renderPage(
      <SkillsContent
        {...baseProps}
        skills={[makeSkill({ id: 4, name: 'house-style', origin: 'manual', source: null, package: null, content })]}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Edit house-style' }));
    await userEvent.click(screen.getByRole('button', { name: 'Save changes' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/1/skills/4',
      { content },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('offers both ways to add a skill from the empty state', () => {
    renderPage(<SkillsContent {...baseProps} skills={[]} />);

    expect(screen.getByText('No skills installed')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Browse catalog' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('button', { name: 'Add manually' }).length).toBeGreaterThan(0);
  });
});

describe('SkillsContent — opening the modals', () => {
  it('opens the catalog on the entries it was given', async () => {
    renderPage(<SkillsContent {...baseProps} skills={[]} catalogSkills={[makeCatalogSkill()]} />);

    await userEvent.click(screen.getAllByRole('button', { name: 'Browse catalog' })[0]);

    expect(screen.getByText('Suggested skills')).toBeInTheDocument();
    expect(screen.getByText('Fill PDF forms')).toBeInTheDocument();
  });

  it('opens the manual authoring form', async () => {
    renderPage(<SkillsContent {...baseProps} skills={[]} />);

    await userEvent.click(screen.getAllByRole('button', { name: 'Add manually' })[0]);

    expect(screen.getByLabelText('SKILL.md content')).toBeInTheDocument();
  });

  // Installed packages are what mark a catalog entry as already present; a manual
  // skill has no package, so it can never mark one.
  it('marks an already-installed catalog entry', async () => {
    renderPage(
      <SkillsContent
        {...baseProps}
        skills={[makeSkill({ package: 'anthropics/skills@pdf', name: 'pdf' })]}
        catalogSkills={[makeCatalogSkill()]}
      />,
    );

    await userEvent.click(screen.getAllByRole('button', { name: 'Browse catalog' })[0]);

    expect(screen.getByText('Installed')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^install$/i })).not.toBeInTheDocument();
  });
});
