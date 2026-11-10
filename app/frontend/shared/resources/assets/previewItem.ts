import type { Asset, TaskAsset } from '@/types/generated';

export interface PreviewItem {
  key: string;
  name: string;
  fileUrl: string | null;
  contentType: string | null;
  fileSize: number | null;
  downloadUrl: string;
  authorName?: string | null;
  /** ISO timestamp. */
  date?: string | null;
  /** Library assets only. */
  version?: number;
  /** Library assets only. */
  tags?: string[] | null;
  /** Library assets only: set when the asset is shared publicly. */
  shareUrl?: string | null;
  /** Library assets only: handed back to `onUnshare`. */
  source?: Asset;
}

export function taskAssetToPreviewItem(asset: TaskAsset, authorName: string | null): PreviewItem {
  return {
    key: `task-${asset.id}`,
    name: asset.name,
    fileUrl: asset.fileUrl,
    contentType: asset.contentType,
    fileSize: asset.fileSize,
    downloadUrl: asset.fileUrl ?? '',
    authorName,
    date: asset.createdAt,
  };
}

export function assetToPreviewItem(asset: Asset, downloadUrl: string): PreviewItem {
  return {
    key: `asset-${asset.id}`,
    name: asset.name,
    fileUrl: asset.latestVersion?.fileUrl ?? null,
    contentType: asset.latestVersion?.contentType ?? null,
    fileSize: asset.latestVersion?.fileSize ?? null,
    downloadUrl,
    authorName: asset.createdByName ?? 'Unknown',
    date: asset.updatedAt,
    version: asset.latestVersion?.version ?? 1,
    tags: asset.tags,
    shareUrl: asset.shareUrl,
    source: asset,
  };
}
