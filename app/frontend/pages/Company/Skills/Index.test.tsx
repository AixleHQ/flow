import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Skill } from 'shared/resources/skills/SkillsContent';

import SkillsIndex from './Index';

const skill = (overrides: Partial<Skill> = {}): Skill => ({
  id: 1,
  name: 'pdf-wizard',
  title: null,
  description: 'Generate and parse PDFs',
  package: 'acme@pdf-wizard',
  source: 'acme',
  sourceUrl: null,
  installCount: 0,
  scopeType: 'company',
  scopeId: 1,
  scopeIndicator: 'company',
  registryUrl: '',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

// SkillsIndex reads its data from React props (not usePage), so page props are passed as JSX
// props. renderAuthedPage still seeds the SharedProps that AuthLayout reads (currentUser/etc).
const page = (skills: Skill[] = []) => (
  <SkillsIndex skills={skills} registryQuery="" registryResults={[]} />
);

describe('Company/Skills/Index', () => {
  it('renders the page title and subtitle', () => {
    renderAuthedPage(page([]));

    expect(screen.getByText('Company Skills')).toBeInTheDocument();
    expect(
      screen.getByText(/Skills from skills\.sh registry installed for this company/i),
    ).toBeInTheDocument();
  });

  it('shows the empty state with a browse CTA when no skills are installed', () => {
    renderAuthedPage(page([]));

    expect(screen.getByText('No skills installed')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Browse skills.sh registry' })).toBeInTheDocument();
  });

  it('lists installed skills and filters them by name', async () => {
    renderAuthedPage(
      page([
        skill({ id: 1, name: 'pdf-wizard', package: 'acme@pdf-wizard' }),
        skill({ id: 2, name: 'csv-loader', package: 'acme@csv-loader', source: 'acme' }),
      ]),
    );

    expect(screen.getByText('pdf-wizard')).toBeInTheDocument();
    expect(screen.getByText('csv-loader')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Filter installed skills...'), 'pdf');

    expect(screen.getByText('pdf-wizard')).toBeInTheDocument();
    expect(screen.queryByText('csv-loader')).not.toBeInTheDocument();
  });

  it('shows the "no match" state when the filter matches nothing', async () => {
    renderAuthedPage(page([skill({ name: 'pdf-wizard' })]));

    await userEvent.type(screen.getByPlaceholderText('Filter installed skills...'), 'zzz');

    expect(screen.getByText('No skills match your filter')).toBeInTheDocument();
  });

  it('opens the registry search modal from the "Add from Registry" button', async () => {
    renderAuthedPage(page([]));

    await userEvent.click(screen.getByRole('button', { name: 'Add from Registry' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Search skills.sh Registry')).toBeInTheDocument();
  });
});
