import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Asset } from 'shared/resources/assets/AssetsContent';

import AssetsPage from './AssetsPage';


const project = { id: 7, name: 'Rocket Project' };

const asset = (overrides: Partial<Asset> = {}): Asset => ({
  id: 1,
  name: 'spec.pdf',
  folder: null,
  tags: [],
  public: false,
  scopeType: 'Project',
  scopeId: 7,
  scopeIndicator: 'project',
  status: 'active',
  createdById: 1,
  createdByName: 'Author',
  versionsCount: 1,
  latestVersion: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Projects/Assets/AssetsPage', () => {
  it('renders the heading, subtitle and upload action given seeded props', () => {
    renderAuthedPage(<AssetsPage />, { props: { project, assets: [] } });

    expect(screen.getByText('Project Assets')).toBeInTheDocument();
    expect(
      screen.getByText('Files and artifacts for this project. Company assets are also accessible.'),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Upload' })).toBeInTheDocument();
  });

  it('shows the empty state with an upload CTA when there are no assets', () => {
    renderAuthedPage(<AssetsPage />, { props: { project, assets: [] } });

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Upload your first file' })).toBeInTheDocument();
  });

  it('lists assets and filters them by the search query', async () => {
    renderAuthedPage(<AssetsPage />, {
      props: {
        project,
        assets: [asset({ id: 1, name: 'design.fig' }), asset({ id: 2, name: 'budget.xlsx' })],
      },
    });

    expect(screen.getByText('design.fig')).toBeInTheDocument();
    expect(screen.getByText('budget.xlsx')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search assets...'), 'design');

    expect(screen.getByText('design.fig')).toBeInTheDocument();
    expect(screen.queryByText('budget.xlsx')).not.toBeInTheDocument();
  });

  it('shows the "no assets match your filters" state when the search matches nothing', async () => {
    renderAuthedPage(<AssetsPage />, {
      props: { project, assets: [asset({ name: 'design.fig' })] },
    });

    await userEvent.type(screen.getByPlaceholderText('Search assets...'), 'zzz');

    expect(screen.getByText('No assets match your filters')).toBeInTheDocument();
  });

  it('reloads with the asset id when opening version history', async () => {
    renderAuthedPage(<AssetsPage />, {
      props: { project, assets: [asset({ id: 42, name: 'design.fig' })] },
    });

    const row = screen.getByText('design.fig').closest('tr') as HTMLElement;
    // With no latestVersion only the History and Delete action icons render in the row.
    const [historyButton] = within(row).getAllByRole('button');
    await userEvent.click(historyButton);

    expect(router.reload).toHaveBeenCalledWith(
      expect.objectContaining({ data: { history_asset_id: 42 }, only: ['assetVersions'] }),
    );
  });
});
