import type { Asset, Folder } from './types';

/**
 * Pure helpers for the Assets folder view. The tree a viewer sees is the union of persisted
 * `Folder` rows and every path an `Asset.folder` references (plus each such path's ancestors) —
 * mirrored on the backend by `FolderService#all_folder_paths`. Root is represented throughout as
 * the empty string `''` (matching the reference mockup), never `null`.
 */

export interface FolderNode {
  path: string;
  label: string;
  scopeIndicator: 'company' | 'project';
  /** Whether this path has its own Folder row, vs. existing only because an asset lives under it. */
  persisted: boolean;
}

/** Anything with a nullable `folder` field — `Asset` and the lighter `AssetPickerItem` both qualify. */
export interface FolderBearing {
  folder?: string | null;
}

/** Normalizes a nullable `folder` field to the `''` root sentinel used throughout. */
export function assetFolder(asset: FolderBearing): string {
  return asset.folder ?? '';
}

export function parentPath(path: string): string {
  return path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : '';
}

export function folderLabel(path: string): string {
  return path.includes('/') ? path.slice(path.lastIndexOf('/') + 1) : path;
}

/** Every ancestor of `path`, nearest first — e.g. `'a/b/c'` -> `['a/b', 'a']`. */
export function ancestorPaths(path: string): string[] {
  const out: string[] = [];
  let current = parentPath(path);
  while (current) {
    out.push(current);
    current = parentPath(current);
  }
  return out;
}

export function buildFolderPaths(assets: Asset[], folders: Folder[]): Map<string, FolderNode> {
  const map = new Map<string, FolderNode>();
  folders.forEach((f) => {
    map.set(f.path, { path: f.path, label: folderLabel(f.path), scopeIndicator: f.scopeIndicator, persisted: true });
  });
  assets.forEach((a) => {
    const folder = assetFolder(a);
    if (!folder) return;
    [folder, ...ancestorPaths(folder)].forEach((p) => {
      if (map.has(p)) return;
      map.set(p, { path: p, label: folderLabel(p), scopeIndicator: a.scopeIndicator, persisted: false });
    });
  });
  return map;
}

export function directChildFolders(paths: Map<string, FolderNode>, parent: string): FolderNode[] {
  return [...paths.values()]
    .filter((f) => parentPath(f.path) === parent)
    .sort((a, b) => a.label.localeCompare(b.label));
}

export function directChildAssets<T extends FolderBearing>(assets: T[], parent: string): T[] {
  return assets.filter((a) => assetFolder(a) === parent);
}

/** Every asset transitively under `folderPath`, including ones directly in it. */
export function descendantAssetIds<T extends FolderBearing & { id: number }>(
  assets: T[],
  folderPath: string,
): number[] {
  return assets
    .filter((a) => {
      const folder = assetFolder(a);
      return folder === folderPath || folder.startsWith(`${folderPath}/`);
    })
    .map((a) => a.id);
}

/** The set of folder paths implied by a flat list of folder-bearing items — each one's `folder`
 * plus all of its ancestors. Used by the asset picker, which has no persisted `Folder` rows to
 * union in (see `buildFolderPaths` for the richer, AssetsContent version of this). */
export function derivedFolderPaths<T extends FolderBearing>(items: T[]): Set<string> {
  const set = new Set<string>();
  items.forEach((item) => {
    const folder = assetFolder(item);
    if (!folder) return;
    [folder, ...ancestorPaths(folder)].forEach((p) => set.add(p));
  });
  return set;
}

/** Names already taken directly inside `parent` — folders and files alike (used for collision checks). */
export function siblingNames(paths: Map<string, FolderNode>, assets: Asset[], parent: string): string[] {
  return [
    ...directChildFolders(paths, parent).map((f) => f.label),
    ...directChildAssets(assets, parent).map((a) => a.name),
  ];
}

export function folderItemCount(paths: Map<string, FolderNode>, assets: Asset[], path: string): number {
  return directChildFolders(paths, path).length + directChildAssets(assets, path).length;
}

/** Matches on the file name or its full `folder/name` path, case-insensitive. Empty query = all. */
export function searchAssets(assets: Asset[], query: string): Asset[] {
  const q = query.trim().toLowerCase();
  if (!q) return assets;
  return assets.filter((a) => {
    const folder = assetFolder(a);
    const fullPath = folder ? `${folder}/${a.name}` : a.name;
    return a.name.toLowerCase().includes(q) || fullPath.toLowerCase().includes(q);
  });
}
