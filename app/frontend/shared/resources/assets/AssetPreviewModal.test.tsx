import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import type { Asset } from './AssetsContent';
import { AssetPreviewModal } from './AssetPreviewModal';

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
    createdByName: 'Ada Lovelace',
    versionsCount: 1,
    latestVersion: {
      id: 10,
      version: 3,
      contentType: 'image/png',
      fileSize: 2048,
      source: null,
      fileUrl: 'https://files.example/diagram.png',
      createdAt: '2026-01-01T00:00:00Z',
    },
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-06-01T00:00:00Z',
    ...overrides,
  };
}

describe('AssetPreviewModal', () => {
  it('renders no dialog when asset is null', () => {
    renderPage(<AssetPreviewModal asset={null} onClose={vi.fn()} downloadUrl="/download/1" />);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.queryByText('diagram.png')).not.toBeInTheDocument();
  });

  it('shows the asset name as title plus metadata (author, file size) and tags', () => {
    renderPage(<AssetPreviewModal asset={makeAsset()} onClose={vi.fn()} downloadUrl="/download/1" />);

    expect(screen.getByText('diagram.png')).toBeInTheDocument();
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
    expect(screen.getByText('2.0 KB')).toBeInTheDocument();
    expect(screen.getByText('v3')).toBeInTheDocument();
    expect(screen.getByText('design')).toBeInTheDocument();
    expect(screen.getByText('v2')).toBeInTheDocument();
  });

  it('renders an image preview using the latest version fileUrl', () => {
    renderPage(<AssetPreviewModal asset={makeAsset()} onClose={vi.fn()} downloadUrl="/download/1" />);

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
        source: null,
        fileUrl: 'https://files.example/archive.zip',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/zip" />);

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
        source: null,
        fileUrl: 'https://files.example/notes.txt',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/txt" />);

    await waitFor(() => expect(screen.getByText('hello inline preview')).toBeInTheDocument());
    expect(fetchSpy).toHaveBeenCalledWith('https://files.example/notes.txt', expect.objectContaining({ credentials: 'include' }));

    fetchSpy.mockRestore();
  });

  it('calls onClose when the modal close button is clicked', async () => {
    const onClose = vi.fn();
    // Image preview renders no Download button, so the only button is the modal close control.
    renderPage(<AssetPreviewModal asset={makeAsset()} onClose={onClose} downloadUrl="/download/1" />);

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
        source: null,
        fileUrl: 'https://files.example/clip.mp4',
        createdAt: null,
      },
    });

    const { container } = renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/mp4" />);

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
        source: null,
        fileUrl: 'https://files.example/song.mp3',
        createdAt: null,
      },
    });

    const { container } = renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/mp3" />);

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
        source: null,
        fileUrl: 'https://files.example/report.pdf',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/pdf" />);

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
        source: null,
        fileUrl: 'https://files.example/photo.jpg',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/jpg" />);

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
        source: null,
        fileUrl: null,
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/missing" />);

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
        source: null,
        fileUrl: 'https://files.example/huge.log',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/huge" />);

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
        source: null,
        fileUrl: 'https://files.example/readme.txt',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/readme" />);

    await waitFor(() => expect(screen.getByText(/preview not available/i)).toBeInTheDocument());
    expect(screen.queryByText('should not be shown')).not.toBeInTheDocument();

    fetchSpy.mockRestore();
  });

  it('renders fetched inline SVG markup for svg assets', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: true,
      text: () => Promise.resolve('<svg><title>inline-vector-art</title></svg>'),
    } as Response);

    const asset = makeAsset({
      name: 'logo.svg',
      latestVersion: {
        id: 27,
        version: 1,
        contentType: 'image/svg+xml',
        fileSize: 200,
        source: null,
        fileUrl: 'https://files.example/logo.svg',
        createdAt: null,
      },
    });

    const { container } = renderPage(
      <AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/svg" />,
    );

    await waitFor(() => expect(container.querySelector('svg title')).not.toBeNull());
    expect(container.querySelector('svg title')?.textContent).toBe('inline-vector-art');

    fetchSpy.mockRestore();
  });

  it('falls back to an <img> for svg assets when inline fetch yields no content', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue({
      ok: false,
      text: () => Promise.resolve(''),
    } as Response);

    const asset = makeAsset({
      name: 'vector.svg',
      latestVersion: {
        id: 28,
        version: 1,
        contentType: 'image/svg+xml',
        fileSize: 200,
        source: null,
        fileUrl: 'https://files.example/vector.svg',
        createdAt: null,
      },
    });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/svg" />);

    await waitFor(() =>
      expect(screen.getByRole('img', { name: 'vector.svg' })).toHaveAttribute(
        'src',
        'https://files.example/vector.svg',
      ),
    );

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
        source: null,
        fileUrl: 'https://files.example/tiny.bin',
        createdAt: null,
      },
    });
    const { unmount } = renderPage(
      <AssetPreviewModal asset={bytesAsset} onClose={vi.fn()} downloadUrl="/download/tiny" />,
    );
    expect(screen.getAllByText('512 B').length).toBeGreaterThan(0);
    unmount();

    const gbAsset = makeAsset({
      name: 'movie.bin',
      latestVersion: {
        id: 31,
        version: 1,
        contentType: 'application/octet-stream',
        fileSize: 2 * 1024 * 1024 * 1024,
        source: null,
        fileUrl: 'https://files.example/movie.bin',
        createdAt: null,
      },
    });
    const second = renderPage(<AssetPreviewModal asset={gbAsset} onClose={vi.fn()} downloadUrl="/download/movie" />);
    expect(screen.getAllByText('2.0 GB').length).toBeGreaterThan(0);
    second.unmount();

    const noSizeAsset = makeAsset({ latestVersion: null });
    renderPage(<AssetPreviewModal asset={noSizeAsset} onClose={vi.fn()} downloadUrl="/download/none" />);
    expect(screen.getByText('—')).toBeInTheDocument();
  });

  it('falls back to "Unknown" author and v1 when version metadata is absent', () => {
    const asset = makeAsset({ createdByName: null, latestVersion: null });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/none" />);

    expect(screen.getByText('Unknown')).toBeInTheDocument();
    expect(screen.getByText('v1')).toBeInTheDocument();
  });

  it('renders no tag badges when the asset has no tags', () => {
    const asset = makeAsset({ tags: [] });

    renderPage(<AssetPreviewModal asset={asset} onClose={vi.fn()} downloadUrl="/download/1" />);

    expect(screen.queryByText('design')).not.toBeInTheDocument();
    expect(screen.queryByText('v2')).not.toBeInTheDocument();
  });
});
