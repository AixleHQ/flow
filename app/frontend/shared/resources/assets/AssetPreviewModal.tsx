import {
  ActionIcon,
  Alert,
  Anchor,
  Badge,
  Box,
  Button,
  Center,
  Code,
  Group,
  Loader,
  Modal,
  ScrollArea,
  Stack,
  Text,
} from '@mantine/core';
import { IconChevronLeft, IconChevronRight, IconDownload, IconFile, IconWorld } from '@tabler/icons-react';
import { useEffect, useState } from 'react';

import type { Asset } from '@/types/generated';

import { formatDateMedium } from 'shared/lib/formatDate';
import { formatFileSize } from 'shared/lib/formatFileSize';

import { MarkdownPreview } from './MarkdownPreview';
import type { PreviewItem } from './previewItem';
import { getPreviewType, MAX_TEXT_SIZE } from './previewType';

interface AssetPreviewModalProps {
  items: PreviewItem[];
  /** `null` or out of range closes the modal. */
  index: number | null;
  onIndexChange: (index: number) => void;
  onClose: () => void;
  /** Offered only to someone who may change the asset. */
  onUnshare?: (asset: Asset) => Promise<boolean>;
}

type TextState = { key: string; status: 'ready'; text: string } | { key: string; status: 'error' };

const isEditableTarget = (target: EventTarget | null) =>
  target instanceof HTMLElement && target.closest('input, textarea, select, [contenteditable]') !== null;

export function AssetPreviewModal({ items, index, onIndexChange, onClose, onUnshare }: AssetPreviewModalProps) {
  const [textState, setTextState] = useState<TextState | null>(null);

  const count = items.length;
  const item = index !== null && index >= 0 && index < count ? items[index] : null;
  const previewType = item ? getPreviewType(item.contentType, item.name) : 'unsupported';
  const itemKey = item?.key;
  const fileUrl = item?.fileUrl ?? null;
  const fileSize = item?.fileSize ?? 0;
  const needsTextFetch = previewType === 'text' || previewType === 'markdown';
  const tooLarge = needsTextFetch && fileSize > MAX_TEXT_SIZE;
  const open = item !== null;
  const canNavigate = count > 1;

  useEffect(() => {
    if (!itemKey || !fileUrl || !needsTextFetch || tooLarge) return;

    const controller = new AbortController();
    // 'omit': a presigned cross-origin URL needs no cookie, and a credentialed request fails CORS against a wildcard origin.
    fetch(fileUrl, { credentials: 'omit', signal: controller.signal })
      .then((res) => (res.ok ? res.text() : null))
      .then((text) => {
        if (controller.signal.aborted) return;
        setTextState(text === null ? { key: itemKey, status: 'error' } : { key: itemKey, status: 'ready', text });
      })
      .catch(() => {
        if (!controller.signal.aborted) setTextState({ key: itemKey, status: 'error' });
      });
    return () => controller.abort();
  }, [itemKey, fileUrl, needsTextFetch, tooLarge]);

  useEffect(() => {
    if (!open || !canNavigate || index === null) return;

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey) return;
      if (isEditableTarget(event.target)) return;
      event.preventDefault();
      onIndexChange(event.key === 'ArrowRight' ? (index + 1) % count : (index - 1 + count) % count);
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [open, canNavigate, index, count, onIndexChange]);

  useEffect(() => {
    if (!open || !canNavigate || index === null) return;

    for (const neighbour of [items[(index + 1) % count], items[(index - 1 + count) % count]]) {
      const type = getPreviewType(neighbour.contentType, neighbour.name);
      if (neighbour.fileUrl && (type === 'image' || type === 'svg')) new Image().src = neighbour.fileUrl;
    }
  }, [open, canNavigate, index, count, items]);

  if (!item || index === null) return null;

  const currentText = textState?.key === item.key ? textState : null;

  const unsupported = (message?: string) => (
    <UnsupportedPreview
      contentType={item.contentType}
      fileSize={item.fileSize}
      downloadUrl={item.downloadUrl}
      message={message}
    />
  );

  const renderPreview = () => {
    if (!fileUrl) return unsupported();

    switch (previewType) {
      case 'image':
        return (
          <Center>
            <img
              key={item.key}
              src={fileUrl}
              alt={item.name}
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
            <img
              key={item.key}
              src={fileUrl}
              alt={item.name}
              style={{ maxWidth: '100%', maxHeight: '70vh', objectFit: 'contain' }}
            />
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
              title={item.name}
              style={{ width: '100%', height: '100%', border: 'none' }}
            />
          </Box>
        );

      case 'text':
      case 'markdown': {
        if (tooLarge) return unsupported('File too large for inline preview');
        if (!currentText) return <PreviewLoader />;
        if (currentText.status === 'error') {
          return unsupported(previewType === 'markdown' ? "Couldn't load preview" : undefined);
        }
        if (previewType === 'markdown') {
          return (
            <ScrollArea.Autosize mah="65vh" maw={760} mx="auto">
              <MarkdownPreview source={currentText.text} />
            </ScrollArea.Autosize>
          );
        }
        return (
          <Code block style={{ maxHeight: '60vh', overflow: 'auto', whiteSpace: 'pre-wrap' }}>
            {currentText.text}
          </Code>
        );
      }

      default:
        return unsupported();
    }
  };

  const goTo = (next: number) => onIndexChange((next + count) % count);

  const metadata = [
    item.version !== undefined ? `v${item.version}` : null,
    item.authorName,
    item.date ? formatDateMedium(item.date) : null,
    formatFileSize(item.fileSize),
  ].filter((part): part is string => Boolean(part));

  const title = (
    <Group gap="sm" wrap="nowrap">
      <Text fw={600} truncate>
        {item.name}
      </Text>
      {canNavigate && (
        <Text fz={12} c="dimmed" style={{ flexShrink: 0 }}>
          {index + 1} / {count}
        </Text>
      )}
    </Group>
  );

  return (
    <Modal opened onClose={onClose} title={title} centered size="xl">
      <Stack gap="md">
        {item.shareUrl && (
          <Alert icon={<IconWorld size={16} />} color="yellow" variant="light" title="Shared publicly">
            <Group justify="space-between" wrap="nowrap" gap="sm">
              <Anchor href={item.shareUrl} target="_blank" rel="noreferrer" fz={13} truncate>
                {item.shareUrl}
              </Anchor>
              {onUnshare && item.source && (
                <Button
                  size="xs"
                  variant="default"
                  onClick={() => void onUnshare(item.source as Asset).then((ok) => ok && onClose())}
                >
                  Stop sharing
                </Button>
              )}
            </Group>
          </Alert>
        )}

        <Group wrap="nowrap" gap="xs" align="center">
          {canNavigate && (
            <ActionIcon variant="default" size="lg" aria-label="Previous asset" onClick={() => goTo(index - 1)}>
              <IconChevronLeft size={18} />
            </ActionIcon>
          )}
          <Box style={{ flex: 1, minWidth: 0 }}>{renderPreview()}</Box>
          {canNavigate && (
            <ActionIcon variant="default" size="lg" aria-label="Next asset" onClick={() => goTo(index + 1)}>
              <IconChevronRight size={18} />
            </ActionIcon>
          )}
        </Group>

        <Group justify="space-between">
          <Group gap="xs">
            {metadata.map((part, i) => (
              <Group key={`${i}-${part}`} gap="xs">
                {i > 0 && (
                  <Text fz={12} c="dimmed">
                    &middot;
                  </Text>
                )}
                <Text fz={12} c="dimmed">
                  {part}
                </Text>
              </Group>
            ))}
          </Group>
          <Group gap="sm">
            {item.tags && item.tags.length > 0 && (
              <Group gap={4}>
                {item.tags.map((tag) => (
                  <Badge key={tag} size="xs" variant="outline">
                    {tag}
                  </Badge>
                ))}
              </Group>
            )}
            {previewType !== 'unsupported' && fileUrl && !tooLarge && currentText?.status !== 'error' && (
              <Button
                component="a"
                href={item.downloadUrl}
                target="_blank"
                rel="noreferrer"
                variant="default"
                size="xs"
                leftSection={<IconDownload size={14} />}
              >
                Download
              </Button>
            )}
          </Group>
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
