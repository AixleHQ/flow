import '@testing-library/jest-dom/vitest';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';

import type { Asset } from '@/types/generated';
import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { AssetPreviewModal } from './AssetPreviewModal';
import { assetToPreviewItem, type PreviewItem } from './previewItem';

function makeAsset(overrides: Partial<Asset> = {}): Asset {
  return {
    id: 1,
    name: 'diagram.png',
    folder: null,
    tags: ['design', 'v2'],
    public: false,
    scopeType: 'Company',
    scopeId: 1,
    scopeIndicator: 'company',
    status: 'active',
    createdById: 7,
    stepRunId: null,
    createdByName: 'Ada Lovelace',
    versionsCount: 1,
    latestVersion: {
      id: 10,
      version: 3,
      contentType: 'image/png',
      fileSize: 2048,
      source: 'upload',
      uploadedById: 7,
      fileUrl: 'https://files.example/diagram.png',
      createdAt: '2026-01-01T00:00:00Z',
    },
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-06-01T00:00:00Z',
    ...overrides,
  };
}

function single(asset: Asset | null, downloadUrl: string) {
  return {
    items: asset ? [assetToPreviewItem(asset, downloadUrl)] : [],
    index: asset ? 0 : null,
    onIndexChange: vi.fn(),
  };
}

describe('AssetPreviewModal', () => {
  it('renders no dialog when asset is null', () => {
    renderPage(<AssetPreviewModal {...single(null, '/download/1')} onClose={vi.fn()} />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.queryByText('diagram.png')).not.toBeInTheDocument();
  });

  it('shows the asset name as title plus metadata (author, file size) and tags', () => {
    renderPage(<AssetPreviewModal {...single(makeAsset(), '/download/1')} onClose={vi.fn()} />);

    expect(screen.getByText('diagram.png')).toBeInTheDocument();
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
    expect(screen.getByText('2.0 KB')).toBeInTheDocument();
    expect(screen.getByText('v3')).toBeInTheDocument();
    expect(screen.getByText('design')).toBeInTheDocument();
    expect(screen.getByText('v2')).toBeInTheDocument();
  });

  it('renders an image preview using the latest version fileUrl', () => {
    renderPage(<AssetPreviewModal {...single(makeAsset(), '/download/1')} onClose={vi.fn()} />);

    const img = screen.getByRole('img', { name: 'diagram.png' });
    expect(img).toHaveAttribute('src', 'https://files.example/diagram.png');
  });

  it('shows an unsupported preview with a working Download link for unknown file types', () => {
    const asset = makeAsset({
      name: 'archive.zip',
      latestVersion: {
        id: 11,
        version: 1,
        contentType: 'application/zip',
        fileSize: 5000,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/archive.zip',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/zip')} onClose={vi.fn()} />);

    expect(screen.getByText(/preview not available/i)).toBeInTheDocument();
    const link = screen.getByRole('link', { name: /download/i });
    expect(link).toHaveAttribute('href', '/download/zip');
  });

  it('fetches and displays inline text content for text files', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      text: () => Promise.resolve('hello inline preview'),
    } as Response);

    const asset = makeAsset({
      name: 'notes.txt',
      latestVersion: {
        id: 12,
        version: 1,
        contentType: 'text/plain',
        fileSize: 100,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/notes.txt',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/txt')} onClose={vi.fn()} />);

    expect(await screen.findByText('hello inline preview')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledWith(
      'https://files.example/notes.txt',
      expect.objectContaining({ credentials: 'omit' }),
    );

    fetchSpy.mockRestore();
  });

  it('calls onClose when the modal close button is clicked', async () => {
    const onClose = vi.fn();
    // Image preview renders no Download button, so the only button is the modal close control.
    renderPage(<AssetPreviewModal {...single(makeAsset(), '/download/1')} onClose={onClose} />);

    await userEvent.click(screen.getByRole('button'));
    expect(onClose).toHaveBeenCalled();
  });

  it('renders a video player for video content types', () => {
    const asset = makeAsset({
      name: 'clip.mp4',
      latestVersion: {
        id: 20,
        version: 1,
        contentType: 'video/mp4',
        fileSize: 4096,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/clip.mp4',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    const { container } = renderPage(<AssetPreviewModal {...single(asset, '/download/mp4')} onClose={vi.fn()} />);

    const video = container.querySelector('video');
    expect(video).not.toBeNull();
    expect(video).toHaveAttribute('src', 'https://files.example/clip.mp4');
    expect(video).toHaveAttribute('controls');
  });

  it('renders an audio player for audio content types', () => {
    const asset = makeAsset({
      name: 'song.mp3',
      latestVersion: {
        id: 21,
        version: 1,
        contentType: 'audio/mpeg',
        fileSize: 3000,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/song.mp3',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    const { container } = renderPage(<AssetPreviewModal {...single(asset, '/download/mp3')} onClose={vi.fn()} />);

    const audio = container.querySelector('audio');
    expect(audio).not.toBeNull();
    expect(audio).toHaveAttribute('src', 'https://files.example/song.mp3');
    expect(audio).toHaveAttribute('controls');
  });

  it('renders a PDF iframe titled by the asset name', () => {
    const asset = makeAsset({
      name: 'report.pdf',
      latestVersion: {
        id: 22,
        version: 1,
        contentType: 'application/pdf',
        fileSize: 9000,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/report.pdf',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/pdf')} onClose={vi.fn()} />);

    const iframe = screen.getByTitle('report.pdf');
    expect(iframe).toHaveAttribute('src', 'https://files.example/report.pdf#toolbar=1');
  });

  it('detects the preview type from the file extension when contentType is null', () => {
    const asset = makeAsset({
      name: 'photo.jpg',
      latestVersion: {
        id: 23,
        version: 1,
        contentType: null,
        fileSize: 1234,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/photo.jpg',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/jpg')} onClose={vi.fn()} />);

    const img = screen.getByRole('img', { name: 'photo.jpg' });
    expect(img).toHaveAttribute('src', 'https://files.example/photo.jpg');
  });

  it('renders the unsupported preview (not an image) when fileUrl is missing', () => {
    const asset = makeAsset({
      name: 'missing.png',
      latestVersion: {
        id: 24,
        version: 1,
        contentType: 'image/png',
        fileSize: 500,
        source: 'upload',
        uploadedById: 7,
        fileUrl: null,
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/missing')} onClose={vi.fn()} />);

    expect(screen.queryByRole('img', { name: 'missing.png' })).not.toBeInTheDocument();
    expect(screen.getByText(/preview not available/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /download/i })).toHaveAttribute('href', '/download/missing');
  });

  it('shows a "too large" unsupported preview for oversized text files without fetching', () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    const asset = makeAsset({
      name: 'huge.log',
      latestVersion: {
        id: 25,
        version: 1,
        contentType: 'text/plain',
        fileSize: 3 * 1024 * 1024, // exceeds MAX_TEXT_SIZE (2 MiB)
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/huge.log',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/huge')} onClose={vi.fn()} />);

    expect(screen.getByText(/file too large for inline preview/i)).toBeInTheDocument();
    expect(fetchSpy).not.toHaveBeenCalled();

    fetchSpy.mockRestore();
  });

  it('falls back to the unsupported preview when the text fetch is not ok', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: false,
      text: () => Promise.resolve('should not be shown'),
    } as Response);

    const asset = makeAsset({
      name: 'readme.txt',
      latestVersion: {
        id: 26,
        version: 1,
        contentType: 'text/plain',
        fileSize: 50,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/readme.txt',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    renderPage(<AssetPreviewModal {...single(asset, '/download/readme')} onClose={vi.fn()} />);

    expect(await screen.findByText(/preview not available/i)).toBeInTheDocument();
    expect(screen.queryByText('should not be shown')).not.toBeInTheDocument();

    fetchSpy.mockRestore();
  });

  it('renders svg via <img> and never injects the fetched markup inline (XSS-safe)', async () => {
    // Spy resolves content, but svg must NOT fetch it — an inline injection of
    // attacker SVG would execute script on the app origin (stored XSS).
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      text: () => Promise.resolve('<svg><script>alert(1)</script></svg>'),
    } as Response);

    const asset = makeAsset({
      name: 'logo.svg',
      latestVersion: {
        id: 27,
        version: 1,
        contentType: 'image/svg+xml',
        fileSize: 200,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/logo.svg',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });

    const { container } = renderPage(<AssetPreviewModal {...single(asset, '/download/svg')} onClose={vi.fn()} />);

    // Rendered via <img> pointing at the isolated cross-origin file URL...
    await waitFor(() =>
      expect(screen.getByRole('img', { name: 'logo.svg' })).toHaveAttribute('src', 'https://files.example/logo.svg'),
    );
    // ...the SVG bytes are never fetched (so cannot be injected into the app DOM),
    // and the attacker's <script> payload is nowhere in the rendered markup.
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(container.querySelector('script')).toBeNull();

    fetchSpy.mockRestore();
  });

  it('formats sizes across units and shows a dash for missing size', () => {
    const bytesAsset = makeAsset({
      name: 'tiny.bin',
      latestVersion: {
        id: 30,
        version: 1,
        contentType: 'application/octet-stream',
        fileSize: 512,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/tiny.bin',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });
    const { unmount } = renderPage(<AssetPreviewModal {...single(bytesAsset, '/download/tiny')} onClose={vi.fn()} />);
    expect(screen.getAllByText('512 B').length).toBeGreaterThan(0);
    unmount();

    const gbAsset = makeAsset({
      name: 'movie.bin',
      latestVersion: {
        id: 31,
        version: 1,
        contentType: 'application/octet-stream',
        fileSize: 2 * 1024 * 1024 * 1024,
        source: 'upload',
        uploadedById: 7,
        fileUrl: 'https://files.example/movie.bin',
        createdAt: '2026-01-01T00:00:00Z',
      },
    });
    const { unmount: unmountGb } = renderPage(
      <AssetPreviewModal {...single(gbAsset, '/download/movie')} onClose={vi.fn()} />,
    );
    expect(screen.getAllByText('2.0 GB').length).toBeGreaterThan(0);
    unmountGb();

    const noSizeAsset = makeAsset({ latestVersion: null });
    renderPage(<AssetPreviewModal {...single(noSizeAsset, '/download/none')} onClose={vi.fn()} />);
    expect(screen.getByText('—')).toBeInTheDocument();
  });

  it('falls back to "Unknown" author and v1 when version metadata is absent', () => {
    const asset = makeAsset({ createdByName: undefined, latestVersion: null });

    renderPage(<AssetPreviewModal {...single(asset, '/download/none')} onClose={vi.fn()} />);

    expect(screen.getByText('Unknown')).toBeInTheDocument();
    expect(screen.getByText('v1')).toBeInTheDocument();
  });

  it('renders no tag badges when the asset has no tags', () => {
    const asset = makeAsset({ tags: [] });

    renderPage(<AssetPreviewModal {...single(asset, '/download/1')} onClose={vi.fn()} />);

    expect(screen.queryByText('design')).not.toBeInTheDocument();
    expect(screen.queryByText('v2')).not.toBeInTheDocument();
  });

  describe('a publicly shared asset', () => {
    const shared = () => makeAsset({ public: true, shareUrl: 'https://flow.example/share/abc' });

    it('says so and shows the link anyone can open', () => {
      renderPage(<AssetPreviewModal {...single(shared(), '/download/1')} onClose={vi.fn()} />);

      expect(screen.getByText('Shared publicly')).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'https://flow.example/share/abc' })).toHaveAttribute(
        'href',
        'https://flow.example/share/abc',
      );
    });

    it('stops sharing on request and closes once it has', async () => {
      const onUnshare = vi.fn().mockResolvedValue(true);
      const onClose = vi.fn();
      renderPage(<AssetPreviewModal {...single(shared(), '/download/1')} onClose={onClose} onUnshare={onUnshare} />);

      await userEvent.click(screen.getByRole('button', { name: 'Stop sharing' }));

      expect(onUnshare).toHaveBeenCalledWith(expect.objectContaining({ id: 1 }));
      await waitFor(() => expect(onClose).toHaveBeenCalled());
    });

    it('offers no stop button to someone who cannot change the asset', () => {
      renderPage(<AssetPreviewModal {...single(shared(), '/download/1')} onClose={vi.fn()} />);

      expect(screen.queryByRole('button', { name: 'Stop sharing' })).not.toBeInTheDocument();
    });
  });

  describe('as a carousel over task files', () => {
    const item = (overrides: Partial<PreviewItem> & { key: string; name: string }): PreviewItem => ({
      fileUrl: `https://files.example/${overrides.name}`,
      contentType: 'image/png',
      fileSize: 1024,
      downloadUrl: `https://files.example/${overrides.name}`,
      authorName: 'Ada Lovelace',
      date: '2026-01-02T00:00:00Z',
      ...overrides,
    });

    const three = [
      item({ key: 'task-1', name: 'one.png' }),
      item({ key: 'task-2', name: 'two.jpg', contentType: 'image/jpeg' }),
      item({ key: 'task-3', name: 'three.gif', contentType: 'image/gif' }),
    ];

    function Harness({ items, onClose = vi.fn() }: { items: PreviewItem[]; onClose?: () => void }) {
      const [index, setIndex] = useState<number | null>(0);
      return (
        <>
          <input aria-label="note" />
          <AssetPreviewModal items={items} index={index} onIndexChange={setIndex} onClose={onClose} />
        </>
      );
    }

    it('shows a position counter and wraps around with the arrow keys', async () => {
      renderPage(<Harness items={three} />);

      expect(screen.getByText('1 / 3')).toBeInTheDocument();
      await userEvent.keyboard('{ArrowRight}');
      expect(screen.getByText('2 / 3')).toBeInTheDocument();
      expect(screen.getByRole('img', { name: 'two.jpg' })).toBeInTheDocument();
      await userEvent.keyboard('{ArrowRight}{ArrowRight}');
      expect(screen.getByText('1 / 3')).toBeInTheDocument();
      await userEvent.keyboard('{ArrowLeft}');
      expect(screen.getByText('3 / 3')).toBeInTheDocument();
      expect(screen.getByRole('img', { name: 'three.gif' })).toBeInTheDocument();
    });

    it('moves with the on-screen arrows', async () => {
      renderPage(<Harness items={three} />);

      await userEvent.click(screen.getByRole('button', { name: 'Next asset' }));
      expect(screen.getByText('2 / 3')).toBeInTheDocument();
      await userEvent.click(screen.getByRole('button', { name: 'Previous asset' }));
      await userEvent.click(screen.getByRole('button', { name: 'Previous asset' }));
      expect(screen.getByText('3 / 3')).toBeInTheDocument();
    });

    it('closes on Escape', async () => {
      const onClose = vi.fn();
      renderPage(<Harness items={three} onClose={onClose} />);

      await userEvent.keyboard('{Escape}');
      expect(onClose).toHaveBeenCalled();
    });

    it('leaves the arrow keys to a focused input and ignores modified arrows', async () => {
      const onIndexChange = vi.fn();
      renderPage(<AssetPreviewModal items={three} index={0} onIndexChange={onIndexChange} onClose={vi.fn()} />);

      const input = document.createElement('input');
      document.body.appendChild(input);
      input.focus();
      await userEvent.keyboard('{ArrowRight}');
      input.remove();
      await userEvent.keyboard('{Shift>}{ArrowRight}{/Shift}');
      await userEvent.keyboard('{Control>}{ArrowRight}{/Control}');

      expect(onIndexChange).not.toHaveBeenCalled();
    });

    it('keeps navigating with the latest inline callback without rebinding the key listener', async () => {
      const calls: number[] = [];
      function InlineHarness() {
        const [index, setIndex] = useState(0);
        const [renders, setRenders] = useState(0);
        return (
          <>
            <button onClick={() => setRenders(renders + 1)}>rerender</button>
            <AssetPreviewModal
              items={three}
              index={index}
              onIndexChange={(next) => {
                calls.push(next);
                setIndex(next);
              }}
              onClose={() => {}}
            />
          </>
        );
      }
      const addSpy = vi.spyOn(document, 'addEventListener');
      renderPage(<InlineHarness />);
      const keydownBinds = () => addSpy.mock.calls.filter(([type]) => type === 'keydown').length;
      const before = keydownBinds();

      await userEvent.click(screen.getByRole('button', { name: 'rerender' }));
      await userEvent.click(screen.getByRole('button', { name: 'rerender' }));
      expect(keydownBinds()).toBe(before);

      await userEvent.keyboard('{ArrowRight}');
      expect(screen.getByText('2 / 3')).toBeInTheDocument();
      expect(calls).toEqual([1]);
      addSpy.mockRestore();
    });

    it('shows no navigation for a single item', () => {
      renderPage(<Harness items={three.slice(0, 1)} />);

      expect(screen.queryByRole('button', { name: 'Next asset' })).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Previous asset' })).not.toBeInTheDocument();
      expect(screen.queryByText(/\d \/ \d/)).not.toBeInTheDocument();
    });

    it('does not react to the arrow keys with a single item', async () => {
      const onIndexChange = vi.fn();
      renderPage(
        <AssetPreviewModal items={three.slice(0, 1)} index={0} onIndexChange={onIndexChange} onClose={vi.fn()} />,
      );

      await userEvent.keyboard('{ArrowRight}');
      expect(onIndexChange).not.toHaveBeenCalled();
    });

    it('renders closed when the index is out of range', () => {
      renderPage(<AssetPreviewModal items={three} index={-1} onIndexChange={vi.fn()} onClose={vi.fn()} />);

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    });

    it('offers the item Download link and its metadata in the footer', () => {
      renderPage(<Harness items={three} />);

      expect(screen.getByRole('link', { name: /download/i })).toHaveAttribute('href', 'https://files.example/one.png');
      expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
      expect(screen.getByText('1.0 KB')).toBeInTheDocument();
    });
  });

  describe('markdown files', () => {
    const md = (overrides: Partial<PreviewItem> = {}): PreviewItem => ({
      key: 'task-9',
      name: 'spec.md',
      fileUrl: 'https://files.example/spec.md',
      contentType: 'text/markdown',
      fileSize: 100,
      downloadUrl: 'https://files.example/spec.md',
      ...overrides,
    });
    const answer = (text: string) => ({ ok: true, text: () => Promise.resolve(text) }) as Response;

    it('renders GFM instead of showing raw text', async () => {
      const fetchSpy = vi
        .spyOn(globalThis, 'fetch')
        .mockResolvedValue(
          answer('# Title\n\n- a\n\n| h1 | h2 |\n|---|---|\n| 1 | 2 |\n\n```js\nconst x = 1;\n```\n\n- [x] done\n'),
        );
      renderPage(<AssetPreviewModal items={[md()]} index={0} onIndexChange={vi.fn()} onClose={vi.fn()} />);

      expect(await screen.findByRole('heading', { name: 'Title' })).toBeInTheDocument();
      expect(screen.getByRole('table')).toBeInTheDocument();
      expect(screen.getByText('const x = 1;').closest('pre')).not.toBeNull();
      expect(screen.getByRole('checkbox')).toBeChecked();
      expect(screen.getByRole('checkbox')).toBeDisabled();
      expect(screen.getAllByRole('listitem').length).toBeGreaterThanOrEqual(2);
      fetchSpy.mockRestore();
    });

    it('treats a .md sniffed as text/plain as markdown', async () => {
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(answer('# Sniffed'));
      renderPage(
        <AssetPreviewModal
          items={[md({ contentType: 'text/plain' })]}
          index={0}
          onIndexChange={vi.fn()}
          onClose={vi.fn()}
        />,
      );

      expect(await screen.findByRole('heading', { name: 'Sniffed' })).toBeInTheDocument();
      fetchSpy.mockRestore();
    });

    it('shows a loader until the file arrives', async () => {
      let resolve: (value: Response) => void = () => {};
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockReturnValue(new Promise<Response>((r) => (resolve = r)));
      renderPage(<AssetPreviewModal items={[md()]} index={0} onIndexChange={vi.fn()} onClose={vi.fn()} />);

      expect(document.querySelector('.mantine-Loader-root')).not.toBeNull();
      resolve(answer('# Done'));
      expect(await screen.findByRole('heading', { name: 'Done' })).toBeInTheDocument();
      fetchSpy.mockRestore();
    });

    it('offers Download without fetching when the file is over 2 MB', () => {
      const fetchSpy = vi.spyOn(globalThis, 'fetch');
      renderPage(
        <AssetPreviewModal
          items={[md({ fileSize: 2 * 1024 * 1024 + 1 })]}
          index={0}
          onIndexChange={vi.fn()}
          onClose={vi.fn()}
        />,
      );

      expect(screen.getByText('File too large for inline preview')).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /download/i })).toHaveAttribute('href', 'https://files.example/spec.md');
      expect(fetchSpy).not.toHaveBeenCalled();
      fetchSpy.mockRestore();
    });

    it.each([
      ['a failed response', () => Promise.resolve({ ok: false } as Response)],
      ['a network error', () => Promise.reject(new TypeError('Failed to fetch'))],
    ])('shows an error with Download after %s', async (_label, respond) => {
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(respond);
      renderPage(<AssetPreviewModal items={[md()]} index={0} onIndexChange={vi.fn()} onClose={vi.fn()} />);

      expect(await screen.findByText("Couldn't load preview")).toBeInTheDocument();
      expect(screen.getByRole('link', { name: /download/i })).toHaveAttribute('href', 'https://files.example/spec.md');
      fetchSpy.mockRestore();
    });

    it('never shows a slow earlier file over the one now selected', async () => {
      const resolvers: Record<string, (value: Response) => void> = {};
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(
        (input) =>
          new Promise<Response>((r) => {
            resolvers[String(input)] = r;
          }),
      );
      const items = [
        md({ key: 'task-1', name: 'first.md', fileUrl: 'https://files.example/first.md' }),
        md({ key: 'task-2', name: 'second.md', fileUrl: 'https://files.example/second.md' }),
      ];
      function Harness() {
        const [index, setIndex] = useState(0);
        return <AssetPreviewModal items={items} index={index} onIndexChange={setIndex} onClose={vi.fn()} />;
      }
      renderPage(<Harness />);

      await userEvent.click(screen.getByRole('button', { name: 'Next asset' }));
      await waitFor(() => expect(resolvers['https://files.example/second.md']).toBeDefined());
      resolvers['https://files.example/second.md'](answer('# Second'));
      resolvers['https://files.example/first.md']?.(answer('# First'));

      expect(await screen.findByRole('heading', { name: 'Second' })).toBeInTheDocument();
      expect(screen.queryByRole('heading', { name: 'First' })).not.toBeInTheDocument();
      fetchSpy.mockRestore();
    });
  });
});
