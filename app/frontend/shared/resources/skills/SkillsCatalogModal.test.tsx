import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { SkillsCatalogModal, type CatalogSkill } from './SkillsCatalogModal';

function makeCatalogSkill(overrides: Partial<CatalogSkill> = {}): CatalogSkill {
  return {
    registryId: 'anthropics/skills/pdf',
    source: 'anthropics/skills',
    slug: 'pdf',
    title: null,
    description: 'Fill PDF forms',
    installs: 1200,
    featured: false,
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
  opened: true,
  onClose: vi.fn(),
  pagePath: '/company/projects/1/skills',
  installPath: '/company/projects/1/skills',
  catalogSyncedAt: null,
  installedPackages: new Set<string>(),
};

// Search runs server-side: the mirror only backs the default view, and a typed query
// goes upstream where fuzzy search actually works.
describe('SkillsCatalogModal — server-side search', () => {
  it('typing a query partial-reloads the catalog props', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[]} query="" />);

    await userEvent.type(screen.getByLabelText('Search skills'), 'playwright');

    await waitFor(() =>
      expect(router.get).toHaveBeenCalledWith(
        '/company/projects/1/skills',
        { catalog_q: 'playwright' },
        expect.objectContaining({ only: ['catalogSkills', 'catalogQuery'], preserveState: true }),
      ),
    );
  });

  it('clearing the search asks for the default view again', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[]} query="pdf" />);

    await userEvent.click(screen.getByLabelText('Clear search'));

    await waitFor(() =>
      expect(router.get).toHaveBeenCalledWith('/company/projects/1/skills', { catalog_q: '' }, expect.anything()),
    );
  });
});

describe('SkillsCatalogModal — cards', () => {
  it('labels the default view as suggested rather than most installed', () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[makeCatalogSkill()]} query="" />);

    expect(screen.getByText('Suggested skills')).toBeInTheDocument();
  });

  it('does not claim a suggestion when the list is a search result', () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[makeCatalogSkill()]} query="pdf" />);

    expect(screen.queryByText('Suggested skills')).not.toBeInTheDocument();
  });

  it('shows install counts, which are public upstream data', () => {
    renderPage(
      <SkillsCatalogModal
        {...baseProps}
        catalogSkills={[
          makeCatalogSkill({ installs: 734_415 }),
          makeCatalogSkill({ registryId: 'a/b/c', installs: 0 }),
        ]}
        query="pdf"
      />,
    );

    expect(screen.getByText('734.4K installs')).toBeInTheDocument();
  });

  it('installing posts the registry id', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[makeCatalogSkill()]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: /install/i }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/1/skills',
      { skillId: 'anthropics/skills/pdf' },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows an empty-catalog explanation that points at manual authoring', () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[]} query="" />);

    expect(screen.getByText('The catalog is empty')).toBeInTheDocument();
    expect(screen.getByText(/add a skill by hand/i)).toBeInTheDocument();
  });
});

// Providers disagree — snyk has rated skills "high" that the others call "safe" — so
// the badge carries the worst verdict and the tooltip names each provider.
describe('SkillsCatalogModal — audit badges', () => {
  it('surfaces the worst verdict when a skill was audited', () => {
    renderPage(
      <SkillsCatalogModal
        {...baseProps}
        query="pdf"
        catalogSkills={[
          makeCatalogSkill({
            auditRisk: 'high',
            auditProviders: [
              { provider: 'snyk', risk: 'high', score: null, alerts: null, analyzed_at: '2026-02-17T22:15:27Z' },
              { provider: 'socket', risk: 'safe', score: 90, alerts: 0, analyzed_at: '2026-03-18T16:47:53Z' },
            ],
          }),
        ]}
      />,
    );

    expect(screen.getByText('risk: high')).toBeInTheDocument();
  });

  it('says audited rather than safe when every provider agrees', () => {
    renderPage(
      <SkillsCatalogModal
        {...baseProps}
        query="pdf"
        catalogSkills={[
          makeCatalogSkill({
            auditRisk: 'safe',
            auditProviders: [
              { provider: 'socket', risk: 'safe', score: 90, alerts: 0, analyzed_at: '2026-03-18T16:47:53Z' },
            ],
          }),
        ]}
      />,
    );

    expect(screen.getByText('audited')).toBeInTheDocument();
  });

  // Nobody looking is not the same as nothing found, so an unaudited skill gets no
  // badge at all rather than a reassuring one.
  it('shows no audit badge for an unaudited skill', () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[makeCatalogSkill()]} query="pdf" />);

    expect(screen.queryByText(/^audited$/)).not.toBeInTheDocument();
    expect(screen.queryByText(/^risk:/)).not.toBeInTheDocument();
  });
});

describe('SkillsCatalogModal — search pacing', () => {
  it('does not fire a request while the field is still empty', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[]} query="" />);

    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 400));
    });

    expect(router.get).not.toHaveBeenCalled();
  });

  // The endpoint rejects one character and the server keeps showing the suggested
  // set for it, so asking would only replace a useful grid with "no matches".
  it('does not fire a request for a single character', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[]} query="" />);

    await userEvent.type(screen.getByLabelText('Search skills'), 'r');
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 400));
    });

    expect(router.get).not.toHaveBeenCalled();
  });

  // Otherwise ?catalog_q=… survives in the address bar, and reloading or sharing the
  // page silently reopens on a stale search instead of the default view.
  it('drops the query from the URL when the catalog closes', async () => {
    const onClose = vi.fn();
    renderPage(<SkillsCatalogModal {...baseProps} onClose={onClose} catalogSkills={[]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: 'Close catalog' }));

    expect(onClose).toHaveBeenCalled();
    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/1/skills',
      {},
      expect.objectContaining({ only: ['catalogSkills', 'catalogQuery'] }),
    );
  });
});

// A flagged verdict has to interrupt the install, not decorate it: one click is not
// enough for a skill a scanner rates high or critical.
describe('SkillsCatalogModal — flagged installs', () => {
  const flagged = () =>
    makeCatalogSkill({
      auditRisk: 'critical',
      auditProviders: [
        { provider: 'snyk', risk: 'critical', score: null, alerts: null, analyzed_at: '2026-02-17T22:15:27Z' },
      ],
    });

  it('asks for confirmation instead of installing straight away', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[flagged()]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: /^install$/i }));

    expect(router.post).not.toHaveBeenCalled();
    expect(screen.getByText(/flagged as critical risk/i)).toBeInTheDocument();
  });

  it('installs once the warning is acknowledged', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[flagged()]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: /^install$/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Install anyway' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/1/skills',
      { skillId: 'anthropics/skills/pdf' },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('cancelling the warning installs nothing', async () => {
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[flagged()]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: /^install$/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(router.post).not.toHaveBeenCalled();
    expect(screen.queryByText(/flagged as critical risk/i)).not.toBeInTheDocument();
  });

  // An inconclusive verdict is not a flag; only high/critical (or a label we do not
  // recognise) interrupts.
  it('installs a safe-rated skill without a confirmation step', async () => {
    const safe = makeCatalogSkill({
      auditRisk: 'safe',
      auditProviders: [{ provider: 'socket', risk: 'safe', score: 90, alerts: 0, analyzed_at: null }],
    });
    renderPage(<SkillsCatalogModal {...baseProps} catalogSkills={[safe]} query="pdf" />);

    await userEvent.click(screen.getByRole('button', { name: /^install$/i }));

    expect(router.post).toHaveBeenCalled();
  });
});
