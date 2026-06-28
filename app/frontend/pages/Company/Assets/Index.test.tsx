import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Asset } from 'shared/resources/assets/AssetsContent';

import AssetsIndex from './Index';

const asset = (overrides: Partial<Asset> = {}): Asset => ({
  id: 1,
  name: 'roadmap.pdf',
  folder: null,
  tags: [],
  public: false,
  scopeType: 'Company',
  scopeId: 1,
  scopeIndicator: 'company',
  status: 'active',
  createdById: 1,
  createdByName: 'Alice',
  versionsCount: 1,
  latestVersion: {
    id: 10,
    version: 1,
    contentType: 'application/pdf',
    fileSize: 2048,
    source: 'upload',
    fileUrl: null,
    createdAt: '2026-02-01T00:00:00Z',
  },
  createdAt: '2026-02-01T00:00:00Z',
  updatedAt: '2026-02-01T00:00:00Z',
  ...overrides,
});

describe('Company/Assets/Index', () => {
  it('renders the title and the empty state when there are no assets', () => {
    renderAuthedPage(<AssetsIndex />, { props: { assets: [] } });

    expect(screen.getByText('Company Assets')).toBeInTheDocument();
    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Upload your first file' })).toBeInTheDocument();
  });

  it('lists assets in the table given seeded props', () => {
    renderAuthedPage(<AssetsIndex />, {
      props: {
        assets: [asset({ id: 1, name: 'roadmap.pdf' }), asset({ id: 2, name: 'logo.png', folder: 'brand' })],
      },
    });

    expect(screen.getByText('roadmap.pdf')).toBeInTheDocument();
    expect(screen.getByText('logo.png')).toBeInTheDocument();
  });

  it('filters assets by the search query', async () => {
    renderAuthedPage(<AssetsIndex />, {
      props: {
        assets: [asset({ id: 1, name: 'roadmap.pdf' }), asset({ id: 2, name: 'logo.png' })],
      },
    });

    await userEvent.type(screen.getByPlaceholderText('Search assets...'), 'roadmap');

    expect(screen.getByText('roadmap.pdf')).toBeInTheDocument();
    expect(screen.queryByText('logo.png')).not.toBeInTheDocument();
  });

  it('shows the no-match state when the search matches nothing', async () => {
    renderAuthedPage(<AssetsIndex />, { props: { assets: [asset({ name: 'roadmap.pdf' })] } });

    await userEvent.type(screen.getByPlaceholderText('Search assets...'), 'zzz');

    expect(screen.getByText('No assets match your filters')).toBeInTheDocument();
  });

  it('opens the upload modal when the Upload button is clicked', async () => {
    renderAuthedPage(<AssetsIndex />, { props: { assets: [asset()] } });

    await userEvent.click(screen.getByRole('button', { name: 'Upload' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Upload Assets')).toBeInTheDocument();
  });
});
