import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Center,
  Group,
  Modal,
  Progress,
  Select,
  Stack,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import { IconDownload, IconEye, IconFolder, IconHistory, IconSearch, IconTrash, IconUpload } from '@tabler/icons-react';
import AwsS3 from '@uppy/aws-s3';
import Uppy from '@uppy/core';
import type { Body, Meta } from '@uppy/core';
import { useCallback, useMemo, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { formatDateMedium } from 'shared/lib/formatDate';
import { formatFileSize } from 'shared/lib/formatFileSize';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { downloadApiV1CompanyAssetPath, downloadApiV1ProjectAssetPath } from 'shared/routes';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';

import { AssetPreviewModal } from './AssetPreviewModal';
import type { Asset, AssetVersion } from './types';

export type { Asset, AssetVersion } from './types';

const PRESIGN_URL = '/api/v1/assets/presign';
const MAX_FILE_SIZE = 1024 * 1024 * 1024;

interface CachedFileDescriptor {
  id: string;
  storage: string;
  metadata?: { filename: string };
}

// The filename is the only metadata we send: Shrine's determine_mime_type analyzer needs it to
// derive a content type for formats without magic bytes (.md, .txt, .json, .csv). Size and MIME
// type are deliberately omitted — restore_cached_data re-derives both from the stored bytes, and
// file_size must stay client-untrusted (OutputValidator#validate_size depends on it).
function extractCachedFileData(uploadURL: string, filename: string): CachedFileDescriptor {
  const url = new URL(uploadURL, window.location.origin);
  const pathname = decodeURIComponent(url.pathname.replace(/\+/g, '%20'));
  const cachePrefix = '/cache/';
  const idx = pathname.indexOf(cachePrefix);
  if (idx === -1) throw new Error('Cannot extract cache data from upload URL');
  return { id: pathname.substring(idx + cachePrefix.length), storage: 'cache', metadata: { filename } };
}

interface AssetsContentProps {
  assets: Asset[];
  assetVersions?: AssetVersion[];
  title: string;
  subtitle: string;
  isProjectContext?: boolean;
  apiBasePath: string;
  createEndpoint?: string;
  projectId?: number;
}

const SCOPE_COLORS: Record<string, string> = {
  company: 'blue',
  project: 'gray',
};

export function AssetsContent({
  assets,
  assetVersions,
  title,
  subtitle,
  isProjectContext = false,
  apiBasePath,
  createEndpoint,
  projectId,
}: AssetsContentProps) {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const [folderFilter, setFolderFilter] = useState<string | null>(null);

  const [previewAsset, setPreviewAsset] = useState<Asset | null>(null);

  const [uploadOpen, setUploadOpen] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [isUploading, setIsUploading] = useState(false);
  const [uploadedFiles, setUploadedFiles] = useState<Array<{ name: string; cachedFile: CachedFileDescriptor }>>([]);
  const [uploadFolder, setUploadFolder] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [historyAsset, setHistoryAsset] = useState<Asset | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);

  const openHistory = useCallback((asset: Asset) => {
    setHistoryAsset(asset);
    setHistoryLoading(true);
    router.reload({
      data: { history_asset_id: asset.id },
      only: ['asset_versions'],
      onFinish: () => setHistoryLoading(false),
    });
  }, []);

  // --- Delete ---
  const canDelete = useCallback(
    (asset: Asset) => {
      if (!isProjectContext) return true;
      return asset.scopeIndicator !== 'company';
    },
    [isProjectContext],
  );

  const handleSoftDelete = useCallback(
    (asset: Asset) => {
      if (!canDelete(asset)) return;

      modals.openConfirmModal({
        title: `Delete "${asset.name}"`,
        children: <Text size="sm">This asset will be moved to trash and can be restored within 30 days.</Text>,
        labels: { confirm: 'Move to Trash', cancel: 'Cancel' },
        confirmProps: { color: 'red' },
        onConfirm: () => {
          apiFetch(`${apiBasePath}/${asset.id}`, {
            method: 'DELETE',
            headers: { 'Content-Type': 'application/json' },
          })
            .then((res) => {
              if (res.ok) {
                notifications.show({ message: `"${asset.name}" moved to trash`, color: 'green' });
                router.reload();
              } else {
                notifications.show({ message: 'Failed to delete asset', color: 'red' });
              }
            })
            .catch(() => {
              notifications.show({ message: 'Failed to delete asset', color: 'red' });
            });
        },
      });
    },
    [apiBasePath, canDelete],
  );

  // --- Uppy upload ---
  const uppyRef = useRef<InstanceType<typeof Uppy<Meta, Body>> | null>(null);
  if (!uppyRef.current) {
    uppyRef.current = new Uppy<Meta, Body>({
      restrictions: { maxFileSize: MAX_FILE_SIZE },
      autoProceed: false,
    }).use(AwsS3, {
      shouldUseMultipart: false,
      getUploadParameters: async (file) => {
        const qs = new URLSearchParams({
          filename: file.name ?? 'file',
          type: file.type ?? 'application/octet-stream',
        });
        const res = await apiFetch(`${PRESIGN_URL}?${qs}`);
        const data = await res.json();
        return {
          method: data.method as 'POST' | 'PUT',
          url: data.url,
          fields: data.fields ?? {},
          headers: data.headers ?? {},
        };
      },
    });

    uppyRef.current.on('progress', (progress: number) => setUploadProgress(progress));
    uppyRef.current.on('complete', (result) => {
      const files = (result.successful ?? []).map((f) => {
        const name = f.name ?? 'file';
        return {
          name,
          cachedFile: extractCachedFileData((f as unknown as { uploadURL?: string }).uploadURL ?? '', name),
        };
      });
      setUploadedFiles((prev) => [...prev, ...files]);
      setIsUploading(false);
    });
    uppyRef.current.on('error', () => {
      setIsUploading(false);
      notifications.show({ message: 'Upload failed', color: 'red' });
    });
  }

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || !uppyRef.current) return;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      try {
        uppyRef.current.addFile({ name: file.name, type: file.type, data: file });
      } catch {
        /* duplicate */
      }
    }
    setIsUploading(true);
    uppyRef.current.upload();
    e.target.value = '';
  }, []);

  const handleSaveUpload = useCallback(async () => {
    if (!createEndpoint || uploadedFiles.length === 0) return;
    setIsSaving(true);
    let successCount = 0;

    for (const f of uploadedFiles) {
      try {
        const res = await apiFetch(createEndpoint, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            asset: { name: f.name, folder: uploadFolder || null, file: f.cachedFile },
          }),
        });
        if (res.ok) successCount++;
      } catch {
        /* continue with remaining files */
      }
    }

    setIsSaving(false);
    setUploadOpen(false);
    setUploadedFiles([]);
    setUploadFolder('');
    setUploadProgress(0);
    uppyRef.current?.cancelAll();

    if (successCount > 0) {
      notifications.show({
        message: `${successCount} file${successCount > 1 ? 's' : ''} uploaded`,
        color: 'green',
      });
      router.reload();
    } else {
      notifications.show({ message: 'Failed to save uploaded files', color: 'red' });
    }
  }, [createEndpoint, uploadedFiles, uploadFolder]);

  const handleCloseUpload = useCallback(() => {
    setUploadOpen(false);
    setUploadedFiles([]);
    setUploadFolder('');
    setUploadProgress(0);
    uppyRef.current?.cancelAll();
  }, []);

  // --- Filtering ---
  const folders = useMemo(() => {
    const set = new Set<string>();
    for (const a of assets) if (a.folder) set.add(a.folder);
    return Array.from(set)
      .sort()
      .map((f) => ({ value: f, label: f }));
  }, [assets]);

  const filtered = useMemo(() => {
    return assets.filter((a) => {
      if (search && !a.name.toLowerCase().includes(search.toLowerCase())) return false;
      if (folderFilter && a.folder !== folderFilter) return false;
      return true;
    });
  }, [assets, search, folderFilter]);

  // --- Download URL builder ---
  const downloadUrl = useCallback(
    (asset: Asset) => {
      if (asset.scopeIndicator === 'company' || !projectId) {
        return downloadApiV1CompanyAssetPath(asset.id);
      }
      return downloadApiV1ProjectAssetPath(projectId, asset.id);
    },
    [projectId],
  );

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle={subtitle}
        actions={
          canExecute &&
          createEndpoint && (
            <Button leftSection={<IconUpload size={16} />} onClick={() => setUploadOpen(true)}>
              Upload
            </Button>
          )
        }
      />

      <Group gap="sm" mb="lg">
        <TextInput
          placeholder="Search assets..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        {folders.length > 0 && (
          <Select
            placeholder="All folders"
            data={folders}
            value={folderFilter}
            onChange={setFolderFilter}
            clearable
            size="sm"
            w={180}
          />
        )}
      </Group>

      {filtered.length === 0 ? (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
          }}
        >
          <EmptyState
            icon={<IconFolder size={22} />}
            title={search || folderFilter ? 'No assets match your filters' : 'No assets yet'}
            description={
              search || folderFilter
                ? undefined
                : 'Assets are files your agents can read during a session and write results back to.'
            }
            action={
              !search &&
              !folderFilter &&
              canExecute &&
              createEndpoint && (
                <Button variant="outline" onClick={() => setUploadOpen(true)}>
                  Upload your first file
                </Button>
              )
            }
          />
        </Box>
      ) : (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            overflow: 'hidden',
          }}
        >
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Name
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Folder
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Size
                  </Text>
                </Table.Th>
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Version
                  </Text>
                </Table.Th>
                {isProjectContext && (
                  <Table.Th>
                    <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                      Scope
                    </Text>
                  </Table.Th>
                )}
                <Table.Th>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                    Date
                  </Text>
                </Table.Th>
                <Table.Th w={140}>
                  <Text fz={12} fw={600} c="dimmed" tt="uppercase" ta="right" style={{ letterSpacing: 0.5 }}>
                    Actions
                  </Text>
                </Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((asset) => (
                <Table.Tr key={`${asset.scopeType}-${asset.id}`}>
                  <Table.Td>
                    <Text fz={14} fw={500} c="var(--app-text-primary)">
                      {asset.name}
                    </Text>
                    {asset.latestVersion?.contentType && (
                      <Text fz={12} c="dimmed">
                        {asset.latestVersion.contentType}
                      </Text>
                    )}
                  </Table.Td>
                  <Table.Td>
                    {asset.folder ? (
                      <Group gap={4}>
                        <IconFolder size={14} color="var(--mantine-color-dimmed)" />
                        <Text fz={13}>{asset.folder}</Text>
                      </Group>
                    ) : (
                      <Text fz={13} c="dimmed">
                        —
                      </Text>
                    )}
                  </Table.Td>
                  <Table.Td>
                    <Text fz={13} ff="JetBrains Mono, monospace" c="dimmed">
                      {formatFileSize(asset.latestVersion?.fileSize ?? null)}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Text fz={13} ff="JetBrains Mono, monospace">
                      v{asset.latestVersion?.version ?? 1}
                      {asset.versionsCount > 1 && (
                        <Text component="span" fz={11} c="dimmed" ml={4}>
                          ({asset.versionsCount})
                        </Text>
                      )}
                    </Text>
                  </Table.Td>
                  {isProjectContext && (
                    <Table.Td>
                      <Badge color={SCOPE_COLORS[asset.scopeIndicator] ?? 'gray'} size="sm" variant="light">
                        {asset.scopeIndicator}
                      </Badge>
                    </Table.Td>
                  )}
                  <Table.Td>
                    <Text fz={13} c="dimmed">
                      {formatDateMedium(asset.updatedAt)}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Group gap={4} justify="flex-end">
                      {asset.latestVersion?.fileUrl && (
                        <Tooltip label="Preview">
                          <ActionIcon
                            aria-label="Preview"
                            variant="subtle"
                            size="sm"
                            onClick={() => setPreviewAsset(asset)}
                          >
                            <IconEye size={16} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                      {asset.latestVersion && (
                        <Tooltip label="Download">
                          <ActionIcon
                            aria-label="Preview"
                            variant="subtle"
                            size="sm"
                            component="a"
                            href={downloadUrl(asset)}
                            target="_blank"
                            rel="noopener"
                          >
                            <IconDownload size={16} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                      <Tooltip label="Version history">
                        <ActionIcon aria-label="Download" variant="subtle" size="sm" onClick={() => openHistory(asset)}>
                          <IconHistory size={16} />
                        </ActionIcon>
                      </Tooltip>
                      {canExecute && canDelete(asset) ? (
                        <Tooltip label="Delete">
                          <ActionIcon
                            aria-label="Version history"
                            variant="subtle"
                            size="sm"
                            color="red"
                            onClick={() => handleSoftDelete(asset)}
                          >
                            <IconTrash size={16} />
                          </ActionIcon>
                        </Tooltip>
                      ) : (
                        <Tooltip label="Company-managed">
                          <ActionIcon aria-label="Delete" variant="subtle" size="sm" color="red" disabled>
                            <IconTrash size={16} />
                          </ActionIcon>
                        </Tooltip>
                      )}
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Box>
      )}

      {/* Upload Modal */}
      <Modal opened={uploadOpen} onClose={handleCloseUpload} title="Upload Assets" centered size="md">
        <Stack gap="md">
          {uploadedFiles.length > 0 ? (
            <>
              <Text fz={14} fw={500}>
                {uploadedFiles.length} file{uploadedFiles.length > 1 ? 's' : ''} ready to save:
              </Text>
              <Box
                p="sm"
                style={{
                  border: '1px solid var(--app-border-default)',
                  borderRadius: 'var(--mantine-radius-sm)',
                  maxHeight: 200,
                  overflow: 'auto',
                }}
              >
                <Stack gap={4}>
                  {uploadedFiles.map((f, i) => (
                    <Text key={i} fz={13} ff="JetBrains Mono, monospace">
                      {f.name}
                    </Text>
                  ))}
                </Stack>
              </Box>
              <TextInput
                label="Folder (optional)"
                placeholder="Leave empty for root"
                description="Lowercase letters, numbers, hyphens, underscores"
                value={uploadFolder}
                onChange={(e) => setUploadFolder(e.currentTarget.value)}
              />
              <Group justify="flex-end">
                <Button
                  variant="outline"
                  onClick={() => {
                    setUploadedFiles([]);
                    uppyRef.current?.cancelAll();
                  }}
                >
                  Clear
                </Button>
                <Button onClick={handleSaveUpload} loading={isSaving}>
                  Save {uploadedFiles.length} file{uploadedFiles.length > 1 ? 's' : ''}
                </Button>
              </Group>
            </>
          ) : (
            <>
              <Box
                p="xl"
                ta="center"
                style={{
                  border: '2px dashed var(--app-border-default)',
                  borderRadius: 'var(--mantine-radius-md)',
                  cursor: 'pointer',
                  transition: 'border-color 150ms',
                }}
                onClick={() => fileInputRef.current?.click()}
                onDragOver={(e: React.DragEvent) => {
                  e.preventDefault();
                  e.stopPropagation();
                }}
                onDrop={(e: React.DragEvent) => {
                  e.preventDefault();
                  e.stopPropagation();
                  const files = e.dataTransfer.files;
                  if (!files || !uppyRef.current) return;
                  for (let i = 0; i < files.length; i++) {
                    try {
                      uppyRef.current.addFile({ name: files[i].name, type: files[i].type, data: files[i] });
                    } catch {
                      /* duplicate */
                    }
                  }
                  setIsUploading(true);
                  uppyRef.current.upload();
                }}
              >
                <IconUpload size={32} color="var(--mantine-color-dimmed)" />
                <Text fz={14} c="dimmed" mt="sm">
                  Click to select files or drag &amp; drop
                </Text>
                <Text fz={12} c="dimmed">
                  Max file size: 1 GB &middot; Multiple files supported
                </Text>
              </Box>
              <input ref={fileInputRef} type="file" multiple style={{ display: 'none' }} onChange={handleFileSelect} />
              {isUploading && (
                <Stack gap="xs">
                  <Text fz={12} c="dimmed">
                    Uploading... {uploadProgress}%
                  </Text>
                  <Progress value={uploadProgress} size="sm" animated />
                </Stack>
              )}
            </>
          )}
        </Stack>
      </Modal>

      {/* Preview Modal */}
      <AssetPreviewModal
        asset={previewAsset}
        onClose={() => setPreviewAsset(null)}
        downloadUrl={previewAsset ? downloadUrl(previewAsset) : ''}
      />

      {/* Version History Modal */}
      <Modal
        opened={!!historyAsset}
        onClose={() => setHistoryAsset(null)}
        title={`Version History — ${historyAsset?.name ?? ''}`}
        centered
        size="lg"
      >
        {historyLoading ? (
          <Center py="xl">
            <Text c="dimmed">Loading versions...</Text>
          </Center>
        ) : assetVersions && assetVersions.length > 0 ? (
          <Box
            style={{
              border: '1px solid var(--app-border-default)',
              borderRadius: 'var(--mantine-radius-sm)',
              overflow: 'hidden',
            }}
          >
            <Table highlightOnHover>
              <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
                <Table.Tr>
                  <Table.Th>Version</Table.Th>
                  <Table.Th>Date</Table.Th>
                  <Table.Th>Size</Table.Th>
                  <Table.Th>Source</Table.Th>
                  <Table.Th w={60} />
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {assetVersions.map((v) => (
                  <Table.Tr key={v.id}>
                    <Table.Td>
                      <Text fz={13} ff="JetBrains Mono, monospace">
                        v{v.version}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Text fz={13}>{v.createdAt ? formatDateMedium(v.createdAt) : '—'}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Text fz={13} ff="JetBrains Mono, monospace" c="dimmed">
                        {formatFileSize(v.fileSize ?? null)}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Badge size="xs" variant="light" color="gray">
                        {v.source ?? '—'}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      {v.fileUrl && (
                        <ActionIcon
                          variant="subtle"
                          size="sm"
                          component="a"
                          href={v.fileUrl}
                          target="_blank"
                          rel="noopener"
                        >
                          <IconDownload size={16} />
                        </ActionIcon>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Box>
        ) : (
          <Center py="xl">
            <Stack align="center" gap="xs">
              <Text c="dimmed">No version history available</Text>
              <Text fz={12} c="dimmed">
                This asset only has one version
              </Text>
            </Stack>
          </Center>
        )}
      </Modal>
    </Box>
  );
}
