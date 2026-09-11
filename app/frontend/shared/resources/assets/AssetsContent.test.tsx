import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, within } from 'test/renderPage';
import { emitUppy } from 'test/uppyMock';

import type { Asset, Folder } from './AssetsContent';
import { AssetsContent, resolveAssetDrop } from './AssetsContent';

function makeAsset(over: Partial<Asset> = {}): Asset {
  return {
    id: 1,
    name: 'design-spec.pdf',
    folder: null,
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

function makeFolder(over: Partial<Folder> = {}): Folder {
  return {
    id: 1,
    path: 'docs',
    scopeType: 'Company',
    scopeIndicator: 'company',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...over,
  };
}

// Uppy is stubbed inert (see test/setup.ts), so a finished upload is the 'complete' event the
// component subscribed to, carrying the cache URL the presigned S3 PUT would have produced.
function completeUpload(files: Array<{ name?: string; uploadURL: string }>) {
  act(() => emitUppy('complete', { successful: files }));
}

function lastPostedAsset(): { name: string; folder: string | null; file: Record<string, unknown> } {
  const init = vi.mocked(globalThis.fetch).mock.calls.at(-1)?.[1] as RequestInit;
  return JSON.parse(init.body as string).asset;
}

function lastRequest(): { url: string; init: RequestInit } {
  const call = vi.mocked(globalThis.fetch).mock.calls.at(-1);
  return { url: String(call?.[0]), init: call?.[1] as RequestInit };
}

const baseProps = {
  title: 'Asset Library',
  subtitle: 'All files for this workspace',
  apiBasePath: '/api/v1/company/assets',
  createEndpoint: '/api/v1/company/assets',
  foldersApiBase: '/api/v1/company/folders',
};

describe('AssetsContent', () => {
  // Notifications live in a global Mantine store; the two delete-failure tests both raise the same
  // static "Failed to delete asset" toast, so a leftover from one leaks into the next and makes
  // findByText match two nodes. Clear the store before each test.
  beforeEach(() => {
    notifications.clean();
    try {
      localStorage.clear();
    } catch {
      /* not available in this environment */
    }
  });

  it('renders the header and a row for each seeded root asset', () => {
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

  it('defaults to the folder view: folders and root files are listed, no Folder column', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'root.pdf', folder: null }),
          makeAsset({ id: 2, name: 'nested.pdf', folder: 'docs' }),
        ]}
        folders={[makeFolder({ path: 'docs' })]}
      />,
    );

    expect(screen.getByText('root.pdf')).toBeInTheDocument();
    expect(screen.getByText('docs')).toBeInTheDocument();
    // A file nested in "docs" is not shown at root, and there's no Folder column to reveal it.
    expect(screen.queryByText('nested.pdf')).not.toBeInTheDocument();
    expect(screen.queryByText('Folder')).not.toBeInTheDocument();
  });

  it('navigates into a folder on row click and shows breadcrumbs back to root', async () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[makeAsset({ id: 1, name: 'nested.pdf', folder: 'docs' })]}
        folders={[makeFolder({ path: 'docs' })]}
      />,
    );

    await userEvent.click(screen.getByText('docs'));

    expect(screen.getByText('nested.pdf')).toBeInTheDocument();
    // "docs" now appears only as the current breadcrumb segment — not as a folder row, which
    // would carry a folder icon and an item-count subtitle alongside its own click target.
    expect(screen.queryByRole('button', { name: /rename docs/i })).not.toBeInTheDocument();

    // Breadcrumb back to root.
    await userEvent.click(screen.getByText('Assets'));
    expect(screen.getByText('docs')).toBeInTheDocument();
    expect(screen.queryByText('nested.pdf')).not.toBeInTheDocument();
  });

  it('switches to the All files view: every asset shown flat, with a Folder column', async () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'root.pdf', folder: null }),
          makeAsset({ id: 2, name: 'nested.pdf', folder: 'docs' }),
        ]}
        folders={[makeFolder({ path: 'docs' })]}
      />,
    );

    await userEvent.click(screen.getByText('All files'));

    expect(screen.getByText('root.pdf')).toBeInTheDocument();
    expect(screen.getByText('nested.pdf')).toBeInTheDocument();
    expect(screen.getByText('Folder')).toBeInTheDocument();
    // Folders aren't rows in the flat view.
    expect(screen.queryByRole('button', { name: /docs/ })).not.toBeInTheDocument();
  });

  it('behaves as a flat list with no folder controls when foldersApiBase is not given', () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        foldersApiBase={undefined}
        assets={[
          makeAsset({ id: 1, name: 'root.pdf', folder: null }),
          makeAsset({ id: 2, name: 'nested.pdf', folder: 'docs' }),
        ]}
      />,
    );

    expect(screen.getByText('root.pdf')).toBeInTheDocument();
    expect(screen.getByText('nested.pdf')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /New folder/i })).not.toBeInTheDocument();
    expect(screen.queryByText('Folders')).not.toBeInTheDocument();
  });

  it('shows the empty-root state when there are no assets', () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />);

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /upload your first file/i })).toBeInTheDocument();
    // "New folder" appears twice — once in the page header, once in the empty-state CTA.
    expect(screen.getAllByRole('button', { name: /new folder/i }).length).toBe(2);
  });

  it('shows the empty-folder state, with a folder-scoped upload CTA, inside an empty folder', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'docs' })]} />);

    await userEvent.click(screen.getByText('docs'));

    expect(screen.getByText('This folder is empty')).toBeInTheDocument();
    expect(screen.getByText(/Upload a file into "docs"/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /upload here/i })).toBeInTheDocument();
  });

  it('narrows the list as the search query is typed, flattening across the whole tree', async () => {
    renderPage(
      <AssetsContent
        {...baseProps}
        assets={[
          makeAsset({ id: 1, name: 'alpha-report.pdf', folder: null }),
          makeAsset({ id: 2, name: 'beta-notes.txt', folder: 'docs' }),
        ]}
        folders={[makeFolder({ path: 'docs' })]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search assets/i), 'alpha');

    expect(screen.getByText('alpha-report.pdf')).toBeInTheDocument();
    expect(screen.queryByText('beta-notes.txt')).not.toBeInTheDocument();
  });

  it('search hides breadcrumbs and shows the Folder column, even in folder view', async () => {
    renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'nested.pdf', folder: 'docs' })]} folders={[]} />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search assets/i), 'nested');

    expect(screen.getByText('nested.pdf')).toBeInTheDocument();
    expect(screen.getByText('Folder')).toBeInTheDocument();
    expect(screen.queryByText('Assets', { selector: 'span' })).not.toBeInTheDocument();
  });

  it('opens the upload modal when the Upload button is clicked', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[makeAsset()]} />);

    await userEvent.click(screen.getByRole('button', { name: /^upload$/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Upload Assets')).toBeInTheDocument();
    expect(within(dialog).getByText(/click to select files or drag/i)).toBeInTheDocument();
  });

  it('pre-fills the upload folder field with the folder being browsed', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'docs' })]} />);

    await userEvent.click(screen.getByText('docs'));
    await userEvent.click(screen.getByRole('button', { name: /upload here/i }));

    completeUpload([{ name: 'a.md', uploadURL: 'https://s3.example/cache/xyz-a.md' }]);
    await userEvent.click(await screen.findByRole('button', { name: /save 1 file/i }));

    expect(lastPostedAsset().folder).toBe('docs');
  });

  it('fires router.reload to fetch versions when the history action is clicked', async () => {
    const asset = makeAsset({ id: 42, name: 'history-me.pdf' });
    const { container } = renderPage(<AssetsContent {...baseProps} assets={[asset]} />);

    // Row action icons are tooltip-only; target the history button via its tabler icon.
    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    expect(historyBtn).not.toBeNull();
    await userEvent.click(historyBtn as HTMLButtonElement);

    expect(router.reload).toHaveBeenCalledWith(
      expect.objectContaining({ data: { history_asset_id: 42 }, only: ['asset_versions'] }),
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

    expect(screen.getByText('No matches')).toBeInTheDocument();
    expect(screen.getByText(/No assets match "nonexistent-xyz"/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
  });

  it('hides the Upload button and first-upload CTA when no createEndpoint is given', () => {
    renderPage(<AssetsContent {...baseProps} createEndpoint={undefined} assets={[]} />);

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^upload$/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
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
    const links = within(dialog).getAllByRole('link');
    expect(links).toHaveLength(1);
    expect(links[0]).toHaveAttribute('href', 'https://files.example/v2.pdf');
  });

  it('posts the uploaded filename in the cached-file descriptor, and no client-supplied size or type', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />);
    await userEvent.click(screen.getByRole('button', { name: /upload your first file/i }));

    completeUpload([{ name: 'release-notes.md', uploadURL: 'https://s3.example/cache/9f8e7d-release-notes.md' }]);
    await userEvent.click(await screen.findByRole('button', { name: /save 1 file/i }));

    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/v1/company/assets',
      expect.objectContaining({ method: 'POST' }),
    );
    const { file } = lastPostedAsset();
    expect(file).toEqual({
      id: '9f8e7d-release-notes.md',
      storage: 'cache',
      metadata: { filename: 'release-notes.md' },
    });
    expect(file).not.toHaveProperty('size');
    expect(file).not.toHaveProperty('mime_type');
  });

  it('sends each uploaded file its own filename, falling back to "file" when Uppy reports none', async () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />);
    await userEvent.click(screen.getByRole('button', { name: /upload your first file/i }));

    completeUpload([
      { name: 'rows.csv', uploadURL: 'https://s3.example/cache/aaa111-rows.csv' },
      { uploadURL: 'https://s3.example/cache/bbb222-unnamed' },
    ]);
    await userEvent.click(await screen.findByRole('button', { name: /save 2 files/i }));

    const bodies = vi
      .mocked(globalThis.fetch)
      .mock.calls.map((call) => JSON.parse((call[1] as RequestInit).body as string).asset);
    expect(bodies.map((a) => a.file.metadata.filename)).toEqual(['rows.csv', 'file']);
  });

  it('completes the delete flow: DELETE request, success toast, and reload when confirmed', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'trash-me.pdf' })]} />,
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    await userEvent.click(deleteBtn as HTMLButtonElement);
    await userEvent.click(await screen.findByRole('button', { name: /move to trash/i }));

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

  it('hides the upload and New folder controls for viewers without execute permission', () => {
    renderPage(<AssetsContent {...baseProps} assets={[]} />, {
      props: { projectPermissions: { canExecute: false, canManage: false } },
    });

    expect(screen.getByText('No assets yet')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^upload$/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /upload your first file/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /new folder/i })).not.toBeInTheDocument();
  });

  it('renders a disabled delete action for viewers without execute permission', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'readonly.pdf' })]} />,
      { props: { projectPermissions: { canExecute: false, canManage: false } } },
    );

    const deleteBtn = container.querySelector('.tabler-icon-trash')?.closest('button');
    expect(deleteBtn).toBeDisabled();

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

    const downloadLink = container.querySelector('.tabler-icon-download')?.closest('a');
    expect(downloadLink).toHaveAttribute('href', '/api/v1/company/assets/7/download');
  });

  it('shows the loading placeholder in the history modal until the reload finishes', async () => {
    const { container } = renderPage(
      <AssetsContent {...baseProps} assets={[makeAsset({ id: 8, name: 'loading.pdf' })]} />,
    );

    const historyBtn = container.querySelector('.tabler-icon-history')?.closest('button');
    await userEvent.click(historyBtn as HTMLButtonElement);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Loading versions...')).toBeInTheDocument();
  });

  // === Folder CRUD ===

  describe('folder creation', () => {
    it('creates a folder at the root via the New folder button', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} />);

      // "New folder" appears both in the header and the empty-state CTA; either does the same thing.
      await userEvent.click(screen.getAllByRole('button', { name: /new folder/i })[0]);
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('New folder')).toBeInTheDocument();
      expect(within(dialog).getByText(/creating inside: assets \(root\)/i)).toBeInTheDocument();

      await userEvent.type(within(dialog).getByPlaceholderText('e.g. specs'), 'dashboard');
      await userEvent.click(within(dialog).getByRole('button', { name: /^create$/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/folders');
      expect(init.method).toBe('POST');
      expect(JSON.parse(init.body as string)).toEqual({ folder: { path: 'dashboard' } });
      expect(router.reload).toHaveBeenCalledWith(expect.objectContaining({ only: ['assets', 'folders'] }));
    });

    it('creates a folder inside the folder currently being browsed', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'dashboard' })]} />);

      await userEvent.click(screen.getByText('dashboard'));
      await userEvent.click(screen.getAllByRole('button', { name: /new folder/i })[0]);
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText(/creating inside: dashboard/i)).toBeInTheDocument();

      await userEvent.type(within(dialog).getByPlaceholderText('e.g. specs'), 'specs');
      await userEvent.click(within(dialog).getByRole('button', { name: /^create$/i }));

      expect(JSON.parse(lastRequest().init.body as string)).toEqual({ folder: { path: 'dashboard/specs' } });
    });

    it('shows an inline error and makes no request for an empty name', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} />);

      await userEvent.click(screen.getAllByRole('button', { name: /new folder/i })[0]);
      const dialog = await screen.findByRole('dialog');
      await userEvent.click(within(dialog).getByRole('button', { name: /^create$/i }));

      expect(within(dialog).getByText('Folder name is required.')).toBeInTheDocument();
      expect(globalThis.fetch).not.toHaveBeenCalled();
    });

    it('shows an inline error for a name that collides with an existing sibling folder', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'dashboard' })]} />);

      await userEvent.click(screen.getByRole('button', { name: /new folder/i }));
      const dialog = await screen.findByRole('dialog');
      await userEvent.type(within(dialog).getByPlaceholderText('e.g. specs'), 'dashboard');
      await userEvent.click(within(dialog).getByRole('button', { name: /^create$/i }));

      expect(within(dialog).getByText(/already exists here/i)).toBeInTheDocument();
      expect(globalThis.fetch).not.toHaveBeenCalled();
    });

    it('shows the server error when the create request fails', async () => {
      vi.mocked(globalThis.fetch).mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'Parent folder does not exist.' }), { status: 422 }),
      );
      renderPage(<AssetsContent {...baseProps} assets={[]} />);

      await userEvent.click(screen.getAllByRole('button', { name: /new folder/i })[0]);
      const dialog = await screen.findByRole('dialog');
      await userEvent.type(within(dialog).getByPlaceholderText('e.g. specs'), 'dashboard');
      await userEvent.click(within(dialog).getByRole('button', { name: /^create$/i }));

      expect(await within(dialog).findByText('Parent folder does not exist.')).toBeInTheDocument();
    });
  });

  describe('folder rename', () => {
    it('renames a folder via its row action', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'dashboard' })]} />);

      await userEvent.click(screen.getByRole('button', { name: /rename dashboard/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Rename folder')).toBeInTheDocument();
      expect(within(dialog).getByDisplayValue('dashboard')).toBeInTheDocument();

      await userEvent.clear(within(dialog).getByPlaceholderText('e.g. specs'));
      await userEvent.type(within(dialog).getByPlaceholderText('e.g. specs'), 'dash');
      await userEvent.click(within(dialog).getByRole('button', { name: /^save$/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/folders/relocate');
      expect(init.method).toBe('PATCH');
      expect(JSON.parse(init.body as string)).toEqual({ from_path: 'dashboard', to_path: 'dash' });
    });

    it('does not offer rename/delete for a company-scoped folder in project context', () => {
      renderPage(
        <AssetsContent
          {...baseProps}
          isProjectContext
          assets={[]}
          folders={[makeFolder({ path: 'shared', scopeIndicator: 'company' })]}
        />,
      );

      expect(screen.queryByRole('button', { name: /rename shared/i })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /delete shared/i })).not.toBeInTheDocument();
      expect(screen.getByLabelText('Company-managed')).toBeInTheDocument();
    });

    it('offers rename but not delete for a derived (non-persisted) folder', () => {
      renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ folder: 'derived' })]} folders={[]} />);

      expect(screen.getByRole('button', { name: /rename derived/i })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: /delete derived/i })).not.toBeInTheDocument();
    });
  });

  describe('folder deletion', () => {
    it('deletes an empty folder via its row action', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[]} folders={[makeFolder({ path: 'dashboard' })]} />);

      await userEvent.click(screen.getByRole('button', { name: /delete dashboard/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Delete folder')).toBeInTheDocument();
      await userEvent.click(within(dialog).getByRole('button', { name: /^delete$/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/folders');
      expect(init.method).toBe('DELETE');
      expect(JSON.parse(init.body as string)).toEqual({ path: 'dashboard', recursive: false });
    });

    it('warns and offers "Delete anyway" for a non-empty folder, without blocking the plain Delete path', async () => {
      renderPage(
        <AssetsContent
          {...baseProps}
          assets={[makeAsset({ folder: 'dashboard' })]}
          folders={[makeFolder({ path: 'dashboard' })]}
        />,
      );

      await userEvent.click(screen.getByRole('button', { name: /delete dashboard/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Folder not empty')).toBeInTheDocument();
      expect(within(dialog).getByText(/still has 1 item inside/i)).toBeInTheDocument();
      expect(within(dialog).queryByRole('button', { name: /^delete$/i })).not.toBeInTheDocument();

      await userEvent.click(within(dialog).getByRole('button', { name: /delete anyway/i }));

      expect(JSON.parse(lastRequest().init.body as string)).toEqual({ path: 'dashboard', recursive: true });
    });
  });

  // === Move ===

  describe('move', () => {
    it('moves a file to a chosen folder via its row action', async () => {
      renderPage(
        <AssetsContent
          {...baseProps}
          assets={[makeAsset({ id: 1, name: 'report.pdf', folder: null })]}
          folders={[makeFolder({ path: 'dashboard' })]}
        />,
      );

      await userEvent.click(screen.getByRole('button', { name: /move report\.pdf/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Move report.pdf')).toBeInTheDocument();

      await userEvent.click(within(dialog).getByRole('radio', { name: 'dashboard' }));
      await userEvent.click(within(dialog).getByRole('button', { name: /move here/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/assets/1');
      expect(init.method).toBe('PATCH');
      expect(JSON.parse(init.body as string)).toEqual({ asset: { folder: 'dashboard' } });
      expect(router.reload).toHaveBeenCalledWith(expect.objectContaining({ only: ['assets', 'folders'] }));
    });

    it('moves a file to root', async () => {
      renderPage(
        <AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'report.pdf', folder: 'dashboard' })]} />,
      );

      await userEvent.click(screen.getByText('dashboard'));
      await userEvent.click(screen.getByRole('button', { name: /move report\.pdf/i }));
      const dialog = await screen.findByRole('dialog');
      await userEvent.click(within(dialog).getByRole('radio', { name: /assets \(root\)/i }));
      await userEvent.click(within(dialog).getByRole('button', { name: /move here/i }));

      expect(JSON.parse(lastRequest().init.body as string)).toEqual({ asset: { folder: '' } });
    });

    it('moves a folder via its row action, disabling its own subtree as a destination', async () => {
      renderPage(
        <AssetsContent
          {...baseProps}
          assets={[]}
          folders={[
            makeFolder({ path: 'dashboard' }),
            makeFolder({ path: 'dashboard/specs' }),
            makeFolder({ path: 'archive' }),
          ]}
        />,
      );

      await userEvent.click(screen.getByRole('button', { name: /move dashboard/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Move dashboard')).toBeInTheDocument();
      expect(within(dialog).getByRole('radio', { name: 'dashboard' })).toHaveAttribute('aria-disabled', 'true');
      expect(within(dialog).getByRole('radio', { name: 'dashboard/specs' })).toHaveAttribute('aria-disabled', 'true');

      await userEvent.click(within(dialog).getByRole('radio', { name: 'archive' }));
      await userEvent.click(within(dialog).getByRole('button', { name: /move here/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/folders/relocate');
      expect(JSON.parse(init.body as string)).toEqual({ from_path: 'dashboard', to_path: 'archive/dashboard' });
    });
  });

  // === Bulk select ===

  describe('bulk select', () => {
    // The selection bar's Move/Delete share their accessible name with the identically-labelled
    // per-row action icons, so every query below is scoped to the bar via its aria-label.
    const bulkActions = () => screen.getByRole('group', { name: 'Bulk actions' });

    it('arms checkboxes via Select and bulk-moves the checked files', async () => {
      vi.mocked(globalThis.fetch).mockResolvedValueOnce(
        new Response(JSON.stringify({ succeeded: [1, 2], skipped: [] }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }),
      );
      renderPage(
        <AssetsContent
          {...baseProps}
          assets={[
            makeAsset({ id: 1, name: 'a.pdf', folder: null }),
            makeAsset({ id: 2, name: 'b.pdf', folder: null }),
          ]}
          folders={[makeFolder({ path: 'dashboard' })]}
        />,
      );

      await userEvent.click(screen.getByRole('button', { name: /^select$/i }));
      await userEvent.click(screen.getByRole('checkbox', { name: /select a\.pdf/i }));
      await userEvent.click(screen.getByRole('checkbox', { name: /select b\.pdf/i }));
      expect(screen.getByText('2 selected')).toBeInTheDocument();

      await userEvent.click(within(bulkActions()).getByRole('button', { name: /^move$/i }));
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Move 2 files')).toBeInTheDocument();
      await userEvent.click(within(dialog).getByRole('radio', { name: 'dashboard' }));
      await userEvent.click(within(dialog).getByRole('button', { name: /move here/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/assets/bulk_actions');
      expect(JSON.parse(init.body as string)).toEqual({
        action_type: 'move',
        asset_ids: [1, 2],
        folder: 'dashboard',
      });
      // Selection clears and bulk mode exits once the move completes.
      expect(await screen.findByRole('button', { name: /^select$/i })).toBeInTheDocument();
    });

    it('bulk-deletes the checked files through the confirm modal', async () => {
      vi.mocked(globalThis.fetch).mockResolvedValueOnce(
        new Response(JSON.stringify({ succeeded: [1], skipped: [] }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }),
      );
      renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'a.pdf', folder: null })]} />);

      await userEvent.click(screen.getByRole('button', { name: /^select$/i }));
      await userEvent.click(screen.getByRole('checkbox', { name: /select a\.pdf/i }));
      await userEvent.click(within(bulkActions()).getByRole('button', { name: /^delete$/i }));

      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Delete 1 file')).toBeInTheDocument();
      await userEvent.click(within(dialog).getByRole('button', { name: /move to trash/i }));

      const { url, init } = lastRequest();
      expect(url).toBe('/api/v1/company/assets/bulk_actions');
      expect(JSON.parse(init.body as string)).toEqual({ action_type: 'delete', asset_ids: [1], folder: undefined });
    });

    it('Cancel exits bulk mode and drops the selection', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'a.pdf', folder: null })]} />);

      await userEvent.click(screen.getByRole('button', { name: /^select$/i }));
      await userEvent.click(screen.getByRole('checkbox', { name: /select a\.pdf/i }));
      await userEvent.click(within(bulkActions()).getByRole('button', { name: /cancel/i }));

      expect(screen.getByRole('button', { name: /^select$/i })).toBeInTheDocument();
      expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    });

    it('disables Move and Delete while nothing is checked', async () => {
      renderPage(<AssetsContent {...baseProps} assets={[makeAsset({ id: 1, name: 'a.pdf', folder: null })]} />);

      await userEvent.click(screen.getByRole('button', { name: /^select$/i }));

      expect(within(bulkActions()).getByRole('button', { name: /^move$/i })).toBeDisabled();
      expect(within(bulkActions()).getByRole('button', { name: /^delete$/i })).toBeDisabled();
    });
  });

  // === Drag-and-drop drop resolution (pure; the pointer gesture itself isn't exercised in jsdom) ===

  describe('resolveAssetDrop', () => {
    it('resolves an asset dragged onto a folder to a move instruction', () => {
      expect(resolveAssetDrop('asset:7', 'folder:dashboard')).toEqual({ assetId: 7, folder: 'dashboard' });
    });

    it('resolves a drop onto the root-derived folder id', () => {
      expect(resolveAssetDrop('asset:7', 'folder:')).toEqual({ assetId: 7, folder: '' });
    });

    it('returns null when the dragged thing is not an asset', () => {
      expect(resolveAssetDrop('folder:dashboard', 'folder:archive')).toBeNull();
    });

    it('returns null when the drop target is not a folder', () => {
      expect(resolveAssetDrop('asset:7', 'asset:8')).toBeNull();
    });
  });
});
