import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, within } from 'test/renderPage';

import type { Asset } from './AssetsContent';
import { AssetsContent } from './AssetsContent';

function makeAsset(over: Partial<Asset> = {}): Asset {
  return {
    id: 1,
    name: 'design-spec.pdf',
    folder: 'docs',
    tags: [],
    public: false,
    scopeType: 'Company',
    scopeId: 10,
    scopeIndicator: 'company',
    status: 'active',
    createdById: 5,
    createdByName: 'Ada Lovelace',
    versionsCount: 1,
    latestVersion: {
      id: 100,
      version: 1,
      contentType: 'application/pdf',
      fileSize: 2048,
      source: 'upload',
      fileUrl: 'https://files.example/design-spec.pdf',
      createdAt: '2026-01-10T00:00:00Z',
    },
    createdAt: '2026-01-10T00:00:00Z',
    updatedAt: '2026-01-10T00:00:00Z',
    ...over,
  };
}

const baseProps = {
  title: 'Asset Library',
  subtitle: 'All files for this workspace',
  apiBasePath: '/api/v1/company/assets',
  createEndpoint: '/api/v1/company/assets',
};

describe('AssetsContent', () => {
  // Notifications live in a global Mantine store; the two delete-failure tests both raise the same
  // static "Failed to delete asset" toast, so a leftover from one leaks into the next and makes
  // findByText match two nodes. Clear the store before each test.
  beforeEach(() => notifications.clean());

  it('renders the header and a row for each seeded asset', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'alpha-report.pdf' }),
          makeAsset({ id: 2, name: 'beta-notes.txt', folder: null }),
        ]}
      />,
    );

    expect(screen.getByText('Asset Library')).toBeInTheDocument();
    expect(screen.getByText('All files for this workspace')).toBeInTheDocument();
    expect(screen.getByText('alpha-report.pdf')).toBeInTheDocument();
    expect(screen.getByText('beta-notes.txt')).toBeInTheDocument();
  });

  it('shows the empty state when there are no assets', () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />);

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    // With a createEndpoint and no filters, the empty-state offers a first-upload CTA.
    expect(screen.getByRole('button', { name: /upload your first file/i })).toBeInTheDocument();
  });

  it('narrows the list as the search query is typed', async () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[makeAsset({ id: 1, name: 'alpha-report.pdf' }), makeAsset({ id: 2, name: 'beta-notes.txt' })]}
      />,
    );

    expect(screen.getByText('alpha-report.pdf')).toBeInTheDocument();
    expect(screen.getByText('beta-notes.txt')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText(/search assets/i), 'alpha');

    expect(screen.getByText('alpha-report.pdf')).toBeInTheDocument();
    expect(screen.queryByText('beta-notes.txt')).not.toBeInTheDocument();
  });

  it('opens the upload modal when the Upload button is clicked', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[makeAsset()]} />);

    await userEvent.click(screen.getByRole('button', { name: /^upload$/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Upload Assets')).toBeInTheDocument();
    expect(within(dialog).getByText(/click to select files or drag/i)).toBeInTheDocument();
  });

  it('fires router.reload to fetch versions when the history action is clicked', async () => {
    const asset = makeAsset({ id: 42, name: 'history-me.pdf' });
    const { container } = renderPage(<AssetsContent {...baseProps} assets={[asset]} />);

    // Row action icons are tooltip-only; target the history button via its tabler icon.
    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    expect(historyBtn).not.toBeNull();
    await userEvent.click(historyBtn as HTMLButtonElement);

    expect(router.reload).toHaveBeenCalledWith(
      expect.objectContaining({ data: { history_asset_id: 42 }, only: ['assetVersions'] }),
    );
  });

  it('runs the delete confirmation flow when the delete action is clicked', async () => {
    const { container } = renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ name: 'trash-me.pdf' })]} />);

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    expect(deleteBtn).not.toBeNull();
    await userEvent.click(deleteBtn as HTMLButtonElement);

    // Mantine confirm modal renders with the asset name in its title and a confirm action.
    expect(await screen.findByText('Delete "trash-me.pdf"')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /move to trash/i })).toBeInTheDocument();
  });

  it('shows the no-match empty state (not the first-upload CTA) when a search filters everything out', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'gamma-doc.pdf' })]} />);

    await userEvent.type(screen.getByPlaceholderText(/search assets/i), 'nonexistent-xyz');

    expect(screen.getByText('No assets match your filters')).toBeInTheDocument();
    // The first-upload CTA only appears when no filters are active.
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
  });

  it('hides the Upload button and first-upload CTA when no createEndpoint is given', () => {
    renderPage(<AssetsContent {...baseProps} createEndpoint={undefined} assets={[]} />);

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^upload$/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
  });

  it('filters the list to a single folder via the folder Select', async () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'spec-in-docs.pdf', folder: 'docs' }),
          makeAsset({ id: 2, name: 'logo-in-brand.png', folder: 'brand' }),
        ]}
      />,
    );

    // Both rows visible before filtering.
    expect(screen.getByText('spec-in-docs.pdf')).toBeInTheDocument();
    expect(screen.getByText('logo-in-brand.png')).toBeInTheDocument();

    // Mantine Select must be opened by clicking before its options are in the DOM.
    await userEvent.click(screen.getByPlaceholderText('All folders'));
    await userEvent.click(await screen.findByRole('option', { name: 'brand' }));

    expect(screen.queryByText('spec-in-docs.pdf')).not.toBeInTheDocument();
    expect(screen.getByText('logo-in-brand.png')).toBeInTheDocument();
  });

  it('does not render the folder Select when no asset has a folder', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'rootless.pdf', folder: null }),
          makeAsset({ id: 2, name: 'also-root.txt', folder: null }),
        ]}
      />,
    );

    expect(screen.queryByPlaceholderText('All folders')).not.toBeInTheDocument();
  });

  it('renders the Scope column and badge in project context', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        isProjectContext
        assets={[
          makeAsset({ id: 1, name: 'company-asset.pdf', scopeIndicator: 'company' }),
          makeAsset({ id: 2, name: 'project-asset.pdf', scopeIndicator: 'project', scopeType: 'Project' }),
        ]}
      />,
    );

    expect(screen.getByText('Scope')).toBeInTheDocument();
    expect(screen.getByText('company')).toBeInTheDocument();
    expect(screen.getByText('project')).toBeInTheDocument();
  });

  it('disables delete for company-managed assets while in project context', async () => {
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        isProjectContext
        assets={[makeAsset({ id: 1, name: 'locked.pdf', scopeIndicator: 'company' })]}
      />,
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    expect(deleteBtn).toBeDisabled();

    // Clicking a disabled delete must not surface a confirm modal.
    await userEvent.click(deleteBtn as HTMLButtonElement);
    expect(screen.queryByText('Delete "locked.pdf"')).not.toBeInTheDocument();
  });

  it('formats human-readable file sizes for the size column', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({
            id: 1,
            name: 'kb-file.txt',
            latestVersion: { ...makeAsset().latestVersion!, id: 1, fileSize: 5120 },
          }),
          makeAsset({
            id: 2,
            name: 'mb-file.zip',
            latestVersion: { ...makeAsset().latestVersion!, id: 2, fileSize: 5 * 1024 * 1024 },
          }),
          makeAsset({
            id: 3,
            name: 'no-size.bin',
            latestVersion: { ...makeAsset().latestVersion!, id: 3, fileSize: null },
          }),
        ]}
      />,
    );

    expect(screen.getByText('5.0 KB')).toBeInTheDocument();
    expect(screen.getByText('5.0 MB')).toBeInTheDocument();
    // Null size renders an em-dash; the no-folder cell also shows one, so allow multiple.
    expect(screen.getAllByText('—').length).toBeGreaterThan(0);
  });

  it('shows the version count badge when an asset has multiple versions', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({
            id: 1,
            name: 'multi-version.pdf',
            versionsCount: 4,
            latestVersion: { ...makeAsset().latestVersion!, version: 4 },
          }),
        ]}
      />,
    );

    expect(screen.getByText('v4')).toBeInTheDocument();
    expect(screen.getByText('(4)')).toBeInTheDocument();
  });

  it('renders a download link pointing at the company asset path', () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 7, scopeIndicator: 'company' })]} />,
    );

    const downloadLink = container.querySelector('.tabler-icon-download')?.closest('a');
    expect(downloadLink).toHaveAttribute('href', '/api/v1/company/assets/7/download');
  });

  it('builds a project-scoped download link when projectId and a project asset are present', () => {
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        isProjectContext
        projectId={99}
        assets={[makeAsset({ id: 7, scopeIndicator: 'project', scopeType: 'Project' })]}
      />,
    );

    const downloadLink = container.querySelector('.tabler-icon-download')?.closest('a');
    expect(downloadLink).toHaveAttribute('href', '/api/v1/projects/99/assets/7/download');
  });

  it('opens the preview modal with the asset name when the preview action is clicked', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'preview-me.pdf' })]} />,
    );

    const previewBtn = container.querySelector('.tabler-icon-eye')?.closest('button');
    expect(previewBtn).not.toBeNull();
    await userEvent.click(previewBtn as HTMLButtonElement);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('preview-me.pdf')).toBeInTheDocument();
  });

  it('omits the preview action when the latest version has no fileUrl', () => {
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({
            id: 1,
            name: 'no-url.pdf',
            latestVersion: { ...makeAsset().latestVersion!, fileUrl: null },
          }),
        ]}
      />,
    );

    expect(container.querySelector('.tabler-icon-eye')).toBeNull();
    // The history action is always present, so the row still has its other actions.
    expect(container.querySelector('.tabler-icon-history')).not.toBeNull();
  });

  it('lists seeded version rows in the history modal', async () => {
    const asset = makeAsset({ id: 5, name: 'versioned.pdf' });
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        assets={[asset]}
        assetVersions={[
          {
            id: 201,
            version: 2,
            contentType: 'application/pdf',
            fileSize: 4096,
            source: 'upload',
            fileUrl: 'https://files.example/v2.pdf',
            createdAt: '2026-02-01T00:00:00Z',
          },
          {
            id: 200,
            version: 1,
            contentType: 'application/pdf',
            fileSize: 2048,
            source: 'import',
            fileUrl: null,
            createdAt: '2026-01-01T00:00:00Z',
          },
        ]}
      />,
    );

    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    await userEvent.click(historyBtn as HTMLButtonElement);

    // router.reload is a spy that never resolves onFinish on its own; invoke it to clear the
    // loading state and reveal the seeded versions table.
    const reloadArgs = (router.reload as unknown as { mock: { calls: [{ onFinish?: () => void }][] } }).mock.calls.at(
      -1,
    )?.[0];
    act(() => reloadArgs?.onFinish?.());

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Version History — versioned.pdf')).toBeInTheDocument();
    expect(within(dialog).getByText('v2')).toBeInTheDocument();
    expect(within(dialog).getByText('v1')).toBeInTheDocument();
    expect(within(dialog).getByText('import')).toBeInTheDocument();
  });

  it('shows the empty history message when no versions are seeded', async () => {
    const asset = makeAsset({ id: 6, name: 'single-version.pdf' });
    const { container } = renderPage(<AssetsContent {...baseProps} assets={[asset]} assetVersions={[]} />);

    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    await userEvent.click(historyBtn as HTMLButtonElement);

    const reloadArgs = (router.reload as unknown as { mock: { calls: [{ onFinish?: () => void }][] } }).mock.calls.at(
      -1,
    )?.[0];
    act(() => reloadArgs?.onFinish?.());

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('No version history available')).toBeInTheDocument();
    expect(within(dialog).getByText('This asset only has one version')).toBeInTheDocument();
  });

  it('shows the content-type subtitle and folder chip in the name/folder cells', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({
            id: 1,
            name: 'typed.csv',
            folder: 'reports',
            latestVersion: { ...makeAsset().latestVersion!, contentType: 'text/csv' },
          }),
        ]}
      />,
    );

    // "reports" appears both as a folder-filter option and in the row cell; scope to the row.
    const row = screen.getByText('typed.csv').closest('tr') as HTMLElement;
    expect(within(row).getByText('text/csv')).toBeInTheDocument();
    expect(within(row).getByText('reports')).toBeInTheDocument();
  });

  it('completes the delete flow: DELETE request, success toast, and reload when confirmed', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'trash-me.pdf' })]} />,
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    await userEvent.click(deleteBtn as HTMLButtonElement);
    await userEvent.click(await screen.findByRole('button', { name: /move to trash/i }));

    // The confirm handler DELETEs the asset's REST path, then reloads + toasts on success.
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/v1/company/assets/1',
      expect.objectContaining({ method: 'DELETE' }),
    );
    expect(await screen.findByText('"trash-me.pdf" moved to trash')).toBeInTheDocument();
    expect(router.reload).toHaveBeenCalled();
  });

  it('shows a failure toast and skips the reload when the delete request is not ok', async () => {
    vi.mocked(globalThis.fetch).mockResolvedValueOnce(new Response(null, { status: 500 }));
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 3, name: 'stubborn.pdf' })]} />,
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    await userEvent.click(deleteBtn as HTMLButtonElement);
    await userEvent.click(await screen.findByRole('button', { name: /move to trash/i }));

    expect(await screen.findByText('Failed to delete asset')).toBeInTheDocument();
    expect(router.reload).not.toHaveBeenCalled();
  });

  it('shows a failure toast when the delete request rejects', async () => {
    vi.mocked(globalThis.fetch).mockRejectedValueOnce(new Error('network down'));
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 4, name: 'flaky.pdf' })]} />,
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    await userEvent.click(deleteBtn as HTMLButtonElement);
    await userEvent.click(await screen.findByRole('button', { name: /move to trash/i }));

    expect(await screen.findByText('Failed to delete asset')).toBeInTheDocument();
    expect(router.reload).not.toHaveBeenCalled();
  });

  it('hides the upload controls for viewers without execute permission', () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />, {
      props: { projectPermissions: { canExecute: false, canManage: false } },
    });

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    // canExecute gates both the header Upload button and the empty-state first-upload CTA.
    expect(screen.queryByRole('button', { name: /^upload$/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
  });

  it('renders a disabled delete action for viewers without execute permission', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'readonly.pdf' })]} />,
      { props: { projectPermissions: { canExecute: false, canManage: false } } },
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    expect(deleteBtn).toBeDisabled();

    // A disabled delete must never surface the confirm modal.
    await userEvent.click(deleteBtn as HTMLButtonElement);
    expect(screen.queryByText('Delete "readonly.pdf"')).not.toBeInTheDocument();
  });

  it('falls back to the company download path for a project asset when no projectId is provided', () => {
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        isProjectContext
        assets={[makeAsset({ id: 7, name: 'orphan.pdf', scopeIndicator: 'project', scopeType: 'Project' })]}
      />,
    );

    // With scopeIndicator 'project' but no projectId, downloadUrl takes the company branch.
    const downloadLink = container.querySelector('.tabler-icon-download')?.closest('a');
    expect(downloadLink).toHaveAttribute('href', '/api/v1/company/assets/7/download');
  });

  it('shows the loading placeholder in the history modal until the reload finishes', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 8, name: 'loading.pdf' })]} />,
    );

    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    await userEvent.click(historyBtn as HTMLButtonElement);

    // router.reload's onFinish never runs on its own, so the modal stays in its loading branch.
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Loading versions...')).toBeInTheDocument();
  });

  it('renders a download link only for history versions that carry a fileUrl', async () => {
    const { container } = renderPage(
      <AssetsContent
        {...baseProps}
        assets={[makeAsset({ id: 9, name: 'linked.pdf' })]}
        assetVersions={[
          {
            id: 301,
            version: 2,
            contentType: 'application/pdf',
            fileSize: 4096,
            source: 'upload',
            fileUrl: 'https://files.example/v2.pdf',
            createdAt: '2026-03-01T00:00:00Z',
          },
          {
            id: 300,
            version: 1,
            contentType: 'application/pdf',
            fileSize: 2048,
            source: 'import',
            fileUrl: null,
            createdAt: '2026-02-01T00:00:00Z',
          },
        ]}
      />,
    );

    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    await userEvent.click(historyBtn as HTMLButtonElement);
    const reloadArgs = (router.reload as unknown as { mock: { calls: [{ onFinish?: () => void }][] } }).mock.calls.at(
      -1,
    )?.[0];
    act(() => reloadArgs?.onFinish?.());

    const dialog = await screen.findByRole('dialog');
    // Only the version with a fileUrl exposes a download anchor; the null-url version has none.
    const links = within(dialog).getAllByRole('link');
    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute('href', 'https://files.example/v2.pdf');
  });
});
