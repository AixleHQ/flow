import { Badge, Box, Button, Center, Code, Group, Loader, Modal, Stack, Text } from '@mantine/core';
import { IconDownload, IconFile } from '@tabler/icons-react';
import { useEffect, useState } from 'react';

import type { Asset } from './AssetsContent';

interface AssetPreviewModalProps {
  asset: Asset | null;
  onClose: () => void;
  downloadUrl: string;
}

function formatFileSize(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

type PreviewType = 'image' | 'video' | 'audio' | 'pdf' | 'text' | 'markdown' | 'svg' | 'unsupported';

function detectPreviewType(contentType: string | null | undefined): PreviewType {
  if (!contentType) return 'unsupported';
  const ct = contentType.toLowerCase();

  if (ct.startsWith('image/svg')) return 'svg';
  if (ct.startsWith('image/')) return 'image';
  if (ct.startsWith('video/')) return 'video';
  if (ct.startsWith('audio/')) return 'audio';
  if (ct === 'application/pdf') return 'pdf';

  if (
    ct.startsWith('text/') ||
    ct.includes('json') ||
    ct.includes('xml') ||
    ct.includes('yaml') ||
    ct.includes('yml') ||
    ct.includes('javascript') ||
    ct.includes('typescript') ||
    ct.includes('css') ||
    ct.includes('html') ||
    ct.includes('sql') ||
    ct.includes('ruby') ||
    ct.includes('python') ||
    ct.includes('shell') ||
    ct.includes('sh') ||
    ct.includes('bash') ||
    ct.includes('csv') ||
    ct.includes('log')
  ) {
    if (ct.includes('markdown') || ct.includes('md')) return 'markdown';
    return 'text';
  }

  return 'unsupported';
}

function extensionFromName(name: string): string {
  const idx = name.lastIndexOf('.');
  return idx > 0 ? name.substring(idx + 1).toLowerCase() : '';
}

function detectPreviewTypeFromExt(name: string): PreviewType {
  const ext = extensionFromName(name);
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico', 'avif'];
  const videoExts = ['mp4', 'webm', 'ogg', 'mov'];
  const audioExts = ['mp3', 'wav', 'ogg', 'aac', 'flac', 'opus', 'wma', 'm4a'];
  const textExts = [
    'txt',
    'log',
    'json',
    'xml',
    'yaml',
    'yml',
    'csv',
    'tsv',
    'js',
    'jsx',
    'ts',
    'tsx',
    'css',
    'scss',
    'less',
    'html',
    'htm',
    'sql',
    'rb',
    'py',
    'go',
    'rs',
    'java',
    'kt',
    'swift',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'php',
    'sh',
    'bash',
    'zsh',
    'fish',
    'toml',
    'ini',
    'cfg',
    'env',
    'gitignore',
    'dockerignore',
    'makefile',
    'rake',
    'gemfile',
    'lock',
    'dockerfile',
  ];
  const mdExts = ['md', 'mdx', 'markdown'];

  if (ext === 'svg') return 'svg';
  if (imageExts.includes(ext)) return 'image';
  if (videoExts.includes(ext)) return 'video';
  if (audioExts.includes(ext)) return 'audio';
  if (ext === 'pdf') return 'pdf';
  if (mdExts.includes(ext)) return 'markdown';
  if (textExts.includes(ext)) return 'text';
  return 'unsupported';
}

function getPreviewType(contentType: string | null | undefined, name: string): PreviewType {
  const fromCt = detectPreviewType(contentType);
  if (fromCt !== 'unsupported') return fromCt;
  return detectPreviewTypeFromExt(name);
}

const MAX_TEXT_SIZE = 2 * 1024 * 1024;

export function AssetPreviewModal({ asset, onClose, downloadUrl }: AssetPreviewModalProps) {
  const [textContent, setTextContent] = useState<string | null>(null);
  const [textLoading, setTextLoading] = useState(false);

  const fileUrl = asset?.latestVersion?.fileUrl ?? null;
  const contentType = asset?.latestVersion?.contentType;
  const previewType = asset ? getPreviewType(contentType, asset.name) : 'unsupported';

  useEffect(() => {
    if (!asset || !fileUrl) {
      setTextContent(null);
      return;
    }

    const needsTextFetch = previewType === 'text' || previewType === 'markdown';
    if (!needsTextFetch) {
      setTextContent(null);
      return;
    }

    const fileSize = asset.latestVersion?.fileSize ?? 0;
    if (fileSize > MAX_TEXT_SIZE) {
      setTextContent(null);
      return;
    }

    setTextLoading(true);
    fetch(fileUrl, { credentials: 'include' })
      .then((res) => (res.ok ? res.text() : null))
      .then((text) => setTextContent(text))
      .catch(() => setTextContent(null))
      .finally(() => setTextLoading(false));
  }, [asset, fileUrl, previewType]);

  if (!asset) return null;

  const renderPreview = () => {
    if (!fileUrl) {
      return (
        <UnsupportedPreview
          contentType={contentType}
          fileSize={asset.latestVersion?.fileSize ?? null}
          downloadUrl={downloadUrl}
        />
      );
    }

    switch (previewType) {
      case 'image':
        return (
          <Center>
            <img
              src={fileUrl}
              alt={asset.name}
              style={{
                maxWidth: '100%',
                maxHeight: '70vh',
                objectFit: 'contain',
                borderRadius: 'var(--mantine-radius-sm)',
              }}
            />
          </Center>
        );

      case 'svg':
        // Render via <img> only. Browsers load SVG in <img> in "secure static
        // mode" — no script execution, no external refs. NEVER inject fetched
        // SVG via dangerouslySetInnerHTML: that runs on the app origin
        // (flow.aixle.com, which holds the session cookie) = stored XSS.
        return (
          <Center>
            <img src={fileUrl} alt={asset.name} style={{ maxWidth: '100%', maxHeight: '70vh', objectFit: 'contain' }} />
          </Center>
        );

      case 'video':
        return (
          <Center>
            <video
              src={fileUrl}
              controls
              style={{ maxWidth: '100%', maxHeight: '70vh', borderRadius: 'var(--mantine-radius-sm)' }}
            >
              Your browser does not support this video format.
            </video>
          </Center>
        );

      case 'audio':
        return (
          <Center py="xl">
            <Stack align="center" gap="md">
              <IconFile size={48} color="var(--mantine-color-dimmed)" />
              <audio src={fileUrl} controls style={{ width: '100%', minWidth: 300 }}>
                Your browser does not support this audio format.
              </audio>
            </Stack>
          </Center>
        );

      case 'pdf':
        return (
          <Box style={{ height: '70vh', borderRadius: 'var(--mantine-radius-sm)', overflow: 'hidden' }}>
            <iframe
              src={`${fileUrl}#toolbar=1`}
              title={asset.name}
              style={{ width: '100%', height: '100%', border: 'none' }}
            />
          </Box>
        );

      case 'text':
      case 'markdown':
        if (textLoading) return <PreviewLoader />;
        if (textContent !== null) {
          return (
            <Code block style={{ maxHeight: '60vh', overflow: 'auto', whiteSpace: 'pre-wrap' }}>
              {textContent}
            </Code>
          );
        }
        if ((asset.latestVersion?.fileSize ?? 0) > MAX_TEXT_SIZE) {
          return (
            <UnsupportedPreview
              contentType={contentType}
              fileSize={asset.latestVersion?.fileSize ?? null}
              downloadUrl={downloadUrl}
              message="File too large for inline preview"
            />
          );
        }
        return (
          <UnsupportedPreview
            contentType={contentType}
            fileSize={asset.latestVersion?.fileSize ?? null}
            downloadUrl={downloadUrl}
          />
        );

      default:
        return (
          <UnsupportedPreview
            contentType={contentType}
            fileSize={asset.latestVersion?.fileSize ?? null}
            downloadUrl={downloadUrl}
          />
        );
    }
  };

  return (
    <Modal opened={!!asset} onClose={onClose} title={asset.name} centered size="xl">
      <Stack gap="md">
        {renderPreview()}

        <Group justify="space-between">
          <Group gap="xs">
            <Text fz={12} c="dimmed">
              v{asset.latestVersion?.version ?? 1}
            </Text>
            <Text fz={12} c="dimmed">
              &middot;
            </Text>
            <Text fz={12} c="dimmed">
              {asset.createdByName ?? 'Unknown'}
            </Text>
            <Text fz={12} c="dimmed">
              &middot;
            </Text>
            <Text fz={12} c="dimmed">
              {formatDate(asset.updatedAt)}
            </Text>
            <Text fz={12} c="dimmed">
              &middot;
            </Text>
            <Text fz={12} c="dimmed">
              {formatFileSize(asset.latestVersion?.fileSize ?? null)}
            </Text>
          </Group>
          {asset.tags?.length > 0 && (
            <Group gap={4}>
              {asset.tags.map((tag) => (
                <Badge key={tag} size="xs" variant="outline">
                  {tag}
                </Badge>
              ))}
            </Group>
          )}
        </Group>
      </Stack>
    </Modal>
  );
}

function PreviewLoader() {
  return (
    <Center py="xl">
      <Loader size="sm" />
    </Center>
  );
}

function UnsupportedPreview({
  contentType,
  fileSize,
  downloadUrl,
  message,
}: {
  contentType?: string | null;
  fileSize: number | null;
  downloadUrl: string;
  message?: string;
}) {
  return (
    <Center py="xl">
      <Stack align="center" gap="sm">
        <IconFile size={48} color="var(--mantine-color-dimmed)" />
        <Text fz={14} c="dimmed">
          {message ?? 'Preview not available for this file type'}
        </Text>
        {contentType && (
          <Text fz={12} c="dimmed">
            {contentType} &middot; {formatFileSize(fileSize)}
          </Text>
        )}
        <Button
          component="a"
          href={downloadUrl}
          target="_blank"
          variant="outline"
          size="sm"
          leftSection={<IconDownload size={16} />}
        >
          Download
        </Button>
      </Stack>
    </Center>
  );
}
