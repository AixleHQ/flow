import { DndContext, PointerSensor, useDraggable, useDroppable, useSensor, useSensors } from '@dnd-kit/core';
import type { DragEndEvent } from '@dnd-kit/core';
import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Center,
  Checkbox,
  Group,
  Modal,
  Progress,
  SegmentedControl,
  Stack,
  Table,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconCheckbox,
  IconDownload,
  IconEye,
  IconFolder,
  IconFolderPlus,
  IconFolderShare,
  IconGripVertical,
  IconHistory,
  IconList,
  IconLock,
  IconPencil,
  IconSearch,
  IconTrash,
  IconUpload,
} from '@tabler/icons-react';
import AwsS3 from '@uppy/aws-s3';
import Uppy from '@uppy/core';
import type { Body, Meta, UppyFile } from '@uppy/core';
import { useCallback, useMemo, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { formatDateMedium } from 'shared/lib/formatDate';
import { formatFileSize } from 'shared/lib/formatFileSize';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { downloadApiV1CompanyAssetPath, downloadApiV1ProjectAssetPath } from 'shared/routes';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';

import { AssetPreviewModal } from './AssetPreviewModal';
import { AssetsBreadcrumbs } from './AssetsBreadcrumbs';
import { AssetsSelectionBar } from './AssetsSelectionBar';
import { DeleteFolderModal } from './DeleteFolderModal';
import { FolderFormModal } from './FolderFormModal';
import {
  type FolderNode,
  buildFolderPaths,
  directChildAssets,
  directChildFolders,
  folderItemCount,
  folderLabel,
  parentPath,
  searchAssets,
  siblingNames,
} from './folderTree';
import { MoveToFolderModal } from './MoveToFolderModal';
import type { Asset, AssetVersion, Folder } from './types';
import { useAssetMutations } from './useAssetMutations';
import { useAssetSelection } from './useAssetSelection';
import { useAssetViewState } from './useAssetViewState';
import { useFolderMutations } from './useFolderMutations';

export type { Asset, AssetVersion, Folder } from './types';

/** What the Move-to-folder modal is currently acting on. */
type MoveTarget = { kind: 'asset'; asset: Asset } | { kind: 'folder'; path: string } | { kind: 'bulk'; ids: number[] };

const ASSET_DRAG_PREFIX = 'asset:';
const FOLDER_DROP_PREFIX = 'folder:';

/** Pure resolver for a drag-and-drop end event's (dnd-kit id, dnd-kit id) pair — extracted so the
 * "what move does this drop mean" logic is unit-testable without simulating a pointer drag in
 * jsdom (the gesture itself isn't exercised there; see AssetsContent.test.tsx). */
export function resolveAssetDrop(activeId: string, overId: string): { assetId: number; folder: string } | null {
  if (!activeId.startsWith(ASSET_DRAG_PREFIX) || !overId.startsWith(FOLDER_DROP_PREFIX)) return null;
  return {
    assetId: Number(activeId.slice(ASSET_DRAG_PREFIX.length)),
    folder: overId.slice(FOLDER_DROP_PREFIX.length),
  };
}

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
  folders?: Folder[];
  title: string;
  subtitle: string;
  isProjectContext?: boolean;
  apiBasePath: string;
  createEndpoint?: string;
  /** Base URL for folder create/relocate/destroy — omitted where folders aren't supported yet. */
  foldersApiBase?: string;
  projectId?: number;
}

const SCOPE_COLORS: Record<string, string> = {
  company: 'blue',
  project: 'gray',
};

/** Modal target for the shared create/rename folder form. */
type FolderFormTarget = { mode: 'create' } | { mode: 'rename'; path: string };

export function AssetsContent({
  assets,
  assetVersions,
  folders = [],
  title,
  subtitle,
  isProjectContext = false,
  apiBasePath,
  createEndpoint,
  foldersApiBase,
  projectId,
}: AssetsContentProps) {
  const { canExecute } = useProjectPermissions();
  const [search, setSearch] = useState('');
  const { viewMode, setViewMode, currentPath, setCurrentPath } = useAssetViewState();

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

  const [folderForm, setFolderForm] = useState<FolderFormTarget | null>(null);
  const [deleteFolderPath, setDeleteFolderPath] = useState<string | null>(null);
  const folderMutations = useFolderMutations(foldersApiBase ?? '');

  const assetMutations = useAssetMutations(apiBasePath);
  const selection = useAssetSelection();
  const [moveTarget, setMoveTarget] = useState<MoveTarget | null>(null);
  const dndSensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));

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
    const uppy = new Uppy<Meta, Body>({
      restrictions: { maxFileSize: MAX_FILE_SIZE },
      autoProceed: false,
    });

    uppy.use(AwsS3, {
      shouldUseMultipart: false,
      // The S3 object key is chosen by the server, not here — /presign mints it and signs a
      // PUT for it, so a client cannot aim an upload at someone else's pending cache entry.
      // signRequest is handed nothing but `{ method, key }`, so the key generated here exists
      // only to carry the Uppy file id across to it.
      generateObjectKey: (file) => file.id,
      signRequest: async ({ key }) => {
        // getFile is typed as always returning a file, but a file removed mid-upload resolves
        // to undefined. The name only picks the cache key's extension, so a fallback is fine.
        const file: UppyFile<Meta, Body> | undefined = uppy.getFile(key);
        const qs = new URLSearchParams({ filename: file?.name ?? 'file' });
        const res = await apiFetch(`${PRESIGN_URL}?${qs}`);
        const data = await res.json();
        return { url: data.url as string };
      },
    });

    uppyRef.current = uppy;

    uppyRef.current.on('progress', (progress: number) => setUploadProgress(progress));
    uppyRef.current.on('complete', (result) => {
      const files = (result.successful ?? []).map((f) => {
        const name = f.name ?? 'file';
        return {
          name,
          cachedFile: extractCachedFileData(f.uploadURL ?? '', name),
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

  const openUpload = useCallback(
    (folder: string) => {
      setUploadFolder(folder);
      setUploadOpen(true);
    },
    [setUploadFolder],
  );

  // --- Folder tree ---
  const paths = useMemo(() => buildFolderPaths(assets, folders), [assets, folders]);
  const query = search.trim();
  const isSearching = query.length > 0;
  const foldersEnabled = !!foldersApiBase;
  // A caller that doesn't wire folders (foldersApiBase omitted) always sees the flat list — the
  // folder-view controls (New folder, the view toggle, breadcrumbs) simply don't appear, rather
  // than navigation silently narrowing the table to whatever the default currentPath happens to be.
  const effectiveViewMode = foldersEnabled ? viewMode : 'flat';

  const folderRows: FolderNode[] =
    isSearching || effectiveViewMode === 'flat' ? [] : directChildFolders(paths, currentPath);
  const fileRows: Asset[] = isSearching
    ? searchAssets(assets, query)
    : effectiveViewMode === 'flat'
      ? assets
      : directChildAssets(assets, currentPath);
  const showFolderColumn = isSearching || effectiveViewMode === 'flat';
  const showBreadcrumbs = foldersEnabled && effectiveViewMode === 'folder' && !isSearching;
  const totalCount = folderRows.length + fileRows.length;
  const countLabel = isSearching
    ? `${fileRows.length} result${fileRows.length === 1 ? '' : 's'}`
    : effectiveViewMode === 'flat'
      ? `${fileRows.length} file${fileRows.length === 1 ? '' : 's'}`
      : `${totalCount} item${totalCount === 1 ? '' : 's'}`;

  // --- Folder CRUD ---
  const openCreateFolder = useCallback(() => setFolderForm({ mode: 'create' }), []);
  const openRenameFolder = useCallback((path: string) => setFolderForm({ mode: 'rename', path }), []);
  const closeFolderForm = useCallback(() => {
    setFolderForm(null);
    folderMutations.setError(null);
  }, [folderMutations]);

  const folderFormExistingNames =
    folderForm?.mode === 'create'
      ? siblingNames(paths, assets, currentPath)
      : folderForm
        ? siblingNames(paths, assets, parentPath(folderForm.path))
        : [];
  const folderFormInitialName = folderForm?.mode === 'rename' ? folderLabel(folderForm.path) : undefined;
  const folderFormParentLabel = currentPath ? folderLabel(currentPath) : '';

  const submitFolderForm = useCallback(
    async (name: string) => {
      if (!folderForm) return;
      const ok =
        folderForm.mode === 'create'
          ? await folderMutations.create(currentPath ? `${currentPath}/${name}` : name)
          : await folderMutations.relocate(
              folderForm.path,
              parentPath(folderForm.path) ? `${parentPath(folderForm.path)}/${name}` : name,
            );
      if (ok) setFolderForm(null);
    },
    [folderForm, folderMutations, currentPath],
  );

  const confirmDeleteFolder = useCallback(
    async (recursive: boolean) => {
      if (!deleteFolderPath) return;
      const result = await folderMutations.destroy(deleteFolderPath, recursive);
      if (result.ok) setDeleteFolderPath(null);
    },
    [deleteFolderPath, folderMutations],
  );

  // --- Move (row action, drag-and-drop, and the bulk-select bar all funnel through this modal) ---
  const allFolderPaths = useMemo(() => [...paths.keys()], [paths]);

  const moveModalSubjectLabel =
    moveTarget?.kind === 'asset'
      ? moveTarget.asset.name
      : moveTarget?.kind === 'folder'
        ? folderLabel(moveTarget.path)
        : moveTarget?.kind === 'bulk'
          ? `${moveTarget.ids.length} file${moveTarget.ids.length === 1 ? '' : 's'}`
          : '';

  // A folder can't be moved into itself or anything nested under it.
  const moveModalDisabledPaths =
    moveTarget?.kind === 'folder'
      ? allFolderPaths.filter((p) => p === moveTarget.path || p.startsWith(`${moveTarget.path}/`))
      : [];

  const confirmMove = useCallback(
    async (destination: string) => {
      if (!moveTarget) return;
      if (moveTarget.kind === 'asset') {
        if (await assetMutations.move(moveTarget.asset.id, destination)) setMoveTarget(null);
      } else if (moveTarget.kind === 'folder') {
        const label = folderLabel(moveTarget.path);
        const to = destination ? `${destination}/${label}` : label;
        if (await folderMutations.relocate(moveTarget.path, to)) setMoveTarget(null);
      } else {
        const result = await assetMutations.bulk('move', moveTarget.ids, destination);
        if (result) {
          setMoveTarget(null);
          selection.exitBulkMode();
        }
      }
    },
    [moveTarget, assetMutations, folderMutations, selection],
  );

  const confirmBulkDelete = useCallback(() => {
    const ids = [...selection.selectedIds];
    if (ids.length === 0) return;
    modals.openConfirmModal({
      title: `Delete ${ids.length} file${ids.length === 1 ? '' : 's'}`,
      children: <Text size="sm">These assets will be moved to trash and can be restored within 30 days.</Text>,
      labels: { confirm: 'Move to Trash', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: async () => {
        if (await assetMutations.bulk('delete', ids)) selection.exitBulkMode();
      },
    });
  }, [selection, assetMutations]);

  // --- Drag-and-drop: a file row onto a folder row moves it there. ---
  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      if (!event.over) return;
      const drop = resolveAssetDrop(String(event.active.id), String(event.over.id));
      if (drop) assetMutations.move(drop.assetId, drop.folder);
    },
    [assetMutations],
  );

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

  const emptyStateKind = isSearching ? 'search' : totalCount > 0 ? null : currentPath ? 'folder' : 'root';

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle={subtitle}
        actions={
          <Group gap="xs">
            {canExecute && foldersEnabled && (
              <Button variant="default" leftSection={<IconFolderPlus size={16} />} onClick={openCreateFolder}>
                New folder
              </Button>
            )}
            {canExecute && createEndpoint && (
              <Button leftSection={<IconUpload size={16} />} onClick={() => openUpload(currentPath)}>
                Upload
              </Button>
            )}
          </Group>
        }
      />

      {selection.bulkMode ? (
        <AssetsSelectionBar
          count={selection.selectedIds.size}
          submitting={assetMutations.submitting}
          onMove={() => setMoveTarget({ kind: 'bulk', ids: [...selection.selectedIds] })}
          onDelete={confirmBulkDelete}
          onExit={selection.exitBulkMode}
        />
      ) : (
        <Group gap="sm" mb={foldersEnabled ? 6 : 'lg'}>
          <TextInput
            placeholder="Search assets..."
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            maw={300}
          />
          {foldersEnabled && (
            <SegmentedControl
              value={viewMode}
              onChange={(v) => setViewMode(v as 'folder' | 'flat')}
              data={[
                { value: 'folder', label: <ViewOptionLabel icon={<IconFolder size={14} />} text="Folders" /> },
                { value: 'flat', label: <ViewOptionLabel icon={<IconList size={14} />} text="All files" /> },
              ]}
            />
          )}
          {fileRows.length > 0 && (
            <Button
              variant="default"
              size="sm"
              leftSection={<IconCheckbox size={14} />}
              onClick={selection.enterBulkMode}
            >
              Select
            </Button>
          )}
          <Text size="sm" c="dimmed" ml="auto">
            {countLabel}
          </Text>
        </Group>
      )}

      {showBreadcrumbs && <AssetsBreadcrumbs currentPath={currentPath} onNavigate={setCurrentPath} />}

      {totalCount === 0 ? (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
          }}
        >
          {emptyStateKind === 'search' ? (
            <EmptyState
              icon={<IconSearch size={22} />}
              title="No matches"
              description={`No assets match "${query}". Try a different name or clear the search.`}
            />
          ) : emptyStateKind === 'folder' ? (
            <EmptyState
              icon={<IconFolder size={22} />}
              title="This folder is empty"
              description={`Upload a file into "${folderLabel(currentPath)}", or create a subfolder to organize further.`}
              action={
                canExecute && (
                  <Group gap="xs">
                    {createEndpoint && (
                      <Button variant="outline" onClick={() => openUpload(currentPath)}>
                        Upload here
                      </Button>
                    )}
                    {foldersEnabled && (
                      <Button variant="default" leftSection={<IconFolderPlus size={16} />} onClick={openCreateFolder}>
                        New folder
                      </Button>
                    )}
                  </Group>
                )
              }
            />
          ) : (
            <EmptyState
              icon={<IconFolder size={22} />}
              title="No assets yet"
              description="Assets are files your agents can read during a session and write results back to."
              action={
                canExecute && (
                  <Group gap="xs">
                    {createEndpoint && (
                      <Button variant="outline" onClick={() => openUpload(currentPath)}>
                        Upload your first file
                      </Button>
                    )}
                    {foldersEnabled && (
                      <Button variant="default" leftSection={<IconFolderPlus size={16} />} onClick={openCreateFolder}>
                        New folder
                      </Button>
                    )}
                  </Group>
                )
              }
            />
          )}
        </Box>
      ) : (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            overflow: 'auto',
          }}
        >
          <DndContext sensors={dndSensors} onDragEnd={handleDragEnd}>
            <Table highlightOnHover miw={showFolderColumn ? 860 : 720}>
              <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
                <Table.Tr>
                  {selection.bulkMode && <Table.Th w={36} />}
                  <Table.Th>
                    <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                      Name
                    </Text>
                  </Table.Th>
                  {showFolderColumn && (
                    <Table.Th>
                      <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
                        Folder
                      </Text>
                    </Table.Th>
                  )}
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
                  <Table.Th w={showFolderColumn ? 168 : 140}>
                    <Text fz={12} fw={600} c="dimmed" tt="uppercase" ta="right" style={{ letterSpacing: 0.5 }}>
                      Actions
                    </Text>
                  </Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {folderRows.map((folder) => (
                  <FolderRow
                    key={folder.path}
                    folder={folder}
                    count={folderItemCount(paths, assets, folder.path)}
                    showFolderColumn={showFolderColumn}
                    isProjectContext={isProjectContext}
                    bulkMode={selection.bulkMode}
                    // Mirrors canDelete(asset): a company-scoped row is only read-only when
                    // viewed from a project — on the Company page itself it's the viewer's own.
                    isCompanyLocked={isProjectContext && folder.scopeIndicator === 'company'}
                    canExecute={canExecute}
                    onNavigate={setCurrentPath}
                    onRename={openRenameFolder}
                    onMove={(path) => setMoveTarget({ kind: 'folder', path })}
                    onDelete={setDeleteFolderPath}
                  />
                ))}
                {fileRows.map((asset) => (
                  <FileRow
                    key={`${asset.scopeType}-${asset.id}`}
                    asset={asset}
                    showFolderColumn={showFolderColumn}
                    isProjectContext={isProjectContext}
                    downloadUrl={downloadUrl(asset)}
                    onPreview={() => setPreviewAsset(asset)}
                    onHistory={() => openHistory(asset)}
                    onDelete={() => handleSoftDelete(asset)}
                    onMove={() => setMoveTarget({ kind: 'asset', asset })}
                    canDelete={canExecute && canDelete(asset)}
                    canMove={canExecute}
                    bulkMode={selection.bulkMode}
                    selected={selection.selectedIds.has(asset.id)}
                    onToggleSelect={() => selection.toggle(asset.id)}
                    draggable={canExecute && !selection.bulkMode}
                  />
                ))}
              </Table.Tbody>
            </Table>
          </DndContext>
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
                description='Use "/" to nest, e.g. specs/api. Letters, digits, hyphens, underscores.'
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

      {/* Create / Rename Folder Modal */}
      {foldersEnabled && (
        <FolderFormModal
          opened={!!folderForm}
          onClose={closeFolderForm}
          mode={folderForm?.mode ?? 'create'}
          parentLabel={folderFormParentLabel}
          initialName={folderFormInitialName}
          existingNames={folderFormExistingNames}
          submitting={folderMutations.submitting}
          serverError={folderMutations.error}
          onSubmit={submitFolderForm}
        />
      )}

      {/* Delete Folder Modal */}
      {foldersEnabled && (
        <DeleteFolderModal
          opened={!!deleteFolderPath}
          onClose={() => setDeleteFolderPath(null)}
          folderLabel={deleteFolderPath ? folderLabel(deleteFolderPath) : ''}
          itemCount={deleteFolderPath ? folderItemCount(paths, assets, deleteFolderPath) : 0}
          submitting={folderMutations.submitting}
          onConfirm={confirmDeleteFolder}
        />
      )}

      {/* Move to Folder Modal — row action, and the bulk-select bar */}
      <MoveToFolderModal
        opened={!!moveTarget}
        onClose={() => setMoveTarget(null)}
        subjectLabel={moveModalSubjectLabel}
        folderPaths={allFolderPaths}
        disabledPaths={moveModalDisabledPaths}
        submitting={assetMutations.submitting}
        onConfirm={confirmMove}
      />
    </Box>
  );
}

function ViewOptionLabel({ icon, text }: { icon: React.ReactNode; text: string }) {
  return (
    <Group gap={6} wrap="nowrap" justify="center">
      {icon}
      <span>{text}</span>
    </Group>
  );
}

interface FolderRowProps {
  folder: FolderNode;
  count: number;
  showFolderColumn: boolean;
  isProjectContext: boolean;
  isCompanyLocked: boolean;
  canExecute: boolean;
  bulkMode: boolean;
  onNavigate: (path: string) => void;
  onRename: (path: string) => void;
  onMove: (path: string) => void;
  onDelete: (path: string) => void;
}

/** A folder row — click navigates into it; it's also a drop target for dragging a file in. */
function FolderRow({
  folder,
  count,
  showFolderColumn,
  isProjectContext,
  isCompanyLocked,
  canExecute,
  bulkMode,
  onNavigate,
  onRename,
  onMove,
  onDelete,
}: FolderRowProps) {
  const { setNodeRef, isOver } = useDroppable({
    id: `${FOLDER_DROP_PREFIX}${folder.path}`,
    disabled: isCompanyLocked,
  });

  return (
    <Table.Tr
      ref={setNodeRef}
      style={{ cursor: 'pointer', background: isOver ? 'var(--app-action-selected)' : undefined }}
      onClick={() => onNavigate(folder.path)}
    >
      {bulkMode && <Table.Td />}
      <Table.Td>
        <Group gap={11} wrap="nowrap">
          <Box
            style={{
              width: 30,
              height: 30,
              flexShrink: 0,
              borderRadius: 7,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: 'var(--app-action-selected)',
              color: 'var(--app-primary-strong)',
            }}
          >
            <IconFolder size={15} />
          </Box>
          <Box style={{ minWidth: 0 }}>
            <Text fz={14} fw={500} c="var(--app-text-primary)" truncate="end" title={folder.label}>
              {folder.label}
            </Text>
            <Text fz={12} c="dimmed">
              {count} item{count === 1 ? '' : 's'}
            </Text>
          </Box>
        </Group>
      </Table.Td>
      {showFolderColumn && <Table.Td />}
      <Table.Td>
        <Text fz={13} c="dimmed">
          —
        </Text>
      </Table.Td>
      <Table.Td>
        <Text fz={13} c="dimmed">
          —
        </Text>
      </Table.Td>
      {isProjectContext && (
        <Table.Td>
          <Text fz={13} c="dimmed">
            —
          </Text>
        </Table.Td>
      )}
      <Table.Td>
        <Text fz={13} c="dimmed">
          —
        </Text>
      </Table.Td>
      <Table.Td onClick={(e) => e.stopPropagation()}>
        {isCompanyLocked ? (
          <Group gap={4} justify="flex-end">
            <Tooltip label="Company-managed">
              <ActionIcon aria-label="Company-managed" variant="subtle" size="sm" disabled>
                <IconLock size={14} />
              </ActionIcon>
            </Tooltip>
          </Group>
        ) : (
          canExecute && (
            <Group gap={4} justify="flex-end">
              <Tooltip label="Rename">
                <ActionIcon
                  aria-label={`Rename ${folder.label}`}
                  variant="subtle"
                  size="sm"
                  onClick={() => onRename(folder.path)}
                >
                  <IconPencil size={14} />
                </ActionIcon>
              </Tooltip>
              <Tooltip label="Move">
                <ActionIcon
                  aria-label={`Move ${folder.label}`}
                  variant="subtle"
                  size="sm"
                  onClick={() => onMove(folder.path)}
                >
                  <IconFolderShare size={14} />
                </ActionIcon>
              </Tooltip>
              {folder.persisted && (
                <Tooltip label="Delete">
                  <ActionIcon
                    aria-label={`Delete ${folder.label}`}
                    variant="subtle"
                    size="sm"
                    color="red"
                    onClick={() => onDelete(folder.path)}
                  >
                    <IconTrash size={14} />
                  </ActionIcon>
                </Tooltip>
              )}
            </Group>
          )
        )}
      </Table.Td>
    </Table.Tr>
  );
}

interface FileRowProps {
  asset: Asset;
  showFolderColumn: boolean;
  isProjectContext: boolean;
  downloadUrl: string;
  onPreview: () => void;
  onHistory: () => void;
  onDelete: () => void;
  onMove: () => void;
  canDelete: boolean;
  canMove: boolean;
  bulkMode: boolean;
  selected: boolean;
  onToggleSelect: () => void;
  draggable: boolean;
}

/** A file row — draggable onto a folder row (outside bulk-select mode) to move it there. */
function FileRow({
  asset,
  showFolderColumn,
  isProjectContext,
  downloadUrl,
  onPreview,
  onHistory,
  onDelete,
  onMove,
  canDelete,
  canMove,
  bulkMode,
  selected,
  onToggleSelect,
  draggable,
}: FileRowProps) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `${ASSET_DRAG_PREFIX}${asset.id}`,
    disabled: !draggable,
  });

  return (
    <Table.Tr ref={setNodeRef} style={{ opacity: isDragging ? 0.4 : 1 }}>
      {bulkMode && (
        <Table.Td onClick={(e) => e.stopPropagation()}>
          <Checkbox checked={selected} onChange={onToggleSelect} aria-label={`Select ${asset.name}`} />
        </Table.Td>
      )}
      <Table.Td>
        <Group gap={6} wrap="nowrap">
          {draggable && (
            // dnd-kit's `attributes` default to role="button" + tabIndex=0, meant for a
            // keyboard-operable drag handle — but only a PointerSensor is configured (no
            // KeyboardSensor), so that role would be a non-functional "button" a screen reader
            // or `getAllByRole('button')` query would trip over. Pointer listeners still work;
            // the handle is just decorative for anything else querying the row.
            <Box
              {...attributes}
              {...listeners}
              role={undefined}
              tabIndex={undefined}
              aria-label={`Drag ${asset.name}`}
              style={{ display: 'flex', cursor: 'grab', touchAction: 'none', flexShrink: 0 }}
            >
              <IconGripVertical size={14} style={{ opacity: 0.35 }} />
            </Box>
          )}
          <Box style={{ minWidth: 0 }}>
            <Text fz={14} fw={500} c="var(--app-text-primary)">
              {asset.name}
            </Text>
            {asset.latestVersion?.contentType && (
              <Text fz={12} c="dimmed">
                {asset.latestVersion.contentType}
              </Text>
            )}
          </Box>
        </Group>
      </Table.Td>
      {showFolderColumn && (
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
      )}
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
              <ActionIcon aria-label="Preview" variant="subtle" size="sm" onClick={onPreview}>
                <IconEye size={16} />
              </ActionIcon>
            </Tooltip>
          )}
          {asset.latestVersion && (
            <Tooltip label="Download">
              <ActionIcon
                aria-label="Download"
                variant="subtle"
                size="sm"
                component="a"
                href={downloadUrl}
                target="_blank"
                rel="noopener"
              >
                <IconDownload size={16} />
              </ActionIcon>
            </Tooltip>
          )}
          <Tooltip label="Version history">
            <ActionIcon aria-label="Version history" variant="subtle" size="sm" onClick={onHistory}>
              <IconHistory size={16} />
            </ActionIcon>
          </Tooltip>
          {canMove && (
            <Tooltip label="Move">
              <ActionIcon aria-label={`Move ${asset.name}`} variant="subtle" size="sm" onClick={onMove}>
                <IconFolderShare size={16} />
              </ActionIcon>
            </Tooltip>
          )}
          {canDelete ? (
            <Tooltip label="Delete">
              <ActionIcon aria-label="Delete" variant="subtle" size="sm" color="red" onClick={onDelete}>
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
  );
}
