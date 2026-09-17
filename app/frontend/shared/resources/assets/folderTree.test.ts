import { describe, expect, it } from 'vitest';

import {
  ancestorPaths,
  buildFolderPaths,
  descendantAssetIds,
  directChildAssets,
  directChildFolders,
  folderItemCount,
  folderLabel,
  parentPath,
  searchAssets,
  siblingNames,
} from './folderTree';
import type { Asset, Folder } from './types';

function asset(over: Partial<Asset> = {}): Asset {
  return {
    id: 1,
    name: 'file.md',
    folder: null,
    tags: [],
    public: false,
    scopeType: 'Project',
    scopeId: 1,
    scopeIndicator: 'project',
    status: 'active',
    createdById: 1,
    createdByName: null,
    versionsCount: 1,
    latestVersion: null,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...over,
  };
}

function folder(over: Partial<Folder> = {}): Folder {
  return {
    id: 1,
    path: 'dashboard',
    scopeType: 'Project',
    scopeIndicator: 'project',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...over,
  };
}

describe('folderTree', () => {
  describe('parentPath / folderLabel / ancestorPaths', () => {
    it('treats a root-level path as having the empty-string parent', () => {
      expect(parentPath('dashboard')).toBe('');
      expect(folderLabel('dashboard')).toBe('dashboard');
      expect(ancestorPaths('dashboard')).toEqual([]);
    });

    it('derives parent/label/ancestors from a nested path', () => {
      expect(parentPath('dashboard/specs')).toBe('dashboard');
      expect(folderLabel('dashboard/specs')).toBe('specs');
      expect(ancestorPaths('a/b/c')).toEqual(['a/b', 'a']);
    });
  });

  describe('buildFolderPaths', () => {
    it('includes every persisted folder', () => {
      const paths = buildFolderPaths([], [folder({ path: 'dashboard' }), folder({ path: 'archive' })]);
      expect([...paths.keys()].sort()).toEqual(['archive', 'dashboard']);
      expect(paths.get('dashboard')?.persisted).toBe(true);
    });

    it('derives a folder from an asset path plus all of its ancestors', () => {
      const paths = buildFolderPaths([asset({ folder: 'dashboard/specs' })], []);
      expect([...paths.keys()].sort()).toEqual(['dashboard', 'dashboard/specs']);
      expect(paths.get('dashboard')?.persisted).toBe(false);
      expect(paths.get('dashboard/specs')?.persisted).toBe(false);
    });

    it('prefers the persisted row when a path is both persisted and derived', () => {
      const paths = buildFolderPaths(
        [asset({ folder: 'dashboard', scopeIndicator: 'company' })],
        [folder({ path: 'dashboard', scopeIndicator: 'project' })],
      );
      expect(paths.get('dashboard')).toEqual({
        path: 'dashboard',
        label: 'dashboard',
        scopeIndicator: 'project',
        persisted: true,
      });
    });

    it('ignores root files (folder: null)', () => {
      const paths = buildFolderPaths([asset({ folder: null })], []);
      expect(paths.size).toBe(0);
    });
  });

  describe('directChildFolders / directChildAssets', () => {
    it('lists only the immediate children of a path, sorted by label', () => {
      const paths = buildFolderPaths(
        [],
        [folder({ path: 'dashboard' }), folder({ path: 'dashboard/specs' }), folder({ path: 'archive' })],
      );
      expect(directChildFolders(paths, '').map((f) => f.path)).toEqual(['archive', 'dashboard']);
      expect(directChildFolders(paths, 'dashboard').map((f) => f.path)).toEqual(['dashboard/specs']);
    });

    it('lists only the files directly in a folder (not nested descendants)', () => {
      const assets = [
        asset({ id: 1, name: 'root.md', folder: null }),
        asset({ id: 2, name: 'top.md', folder: 'dashboard' }),
        asset({ id: 3, name: 'nested.md', folder: 'dashboard/specs' }),
      ];
      expect(directChildAssets(assets, '').map((a) => a.id)).toEqual([1]);
      expect(directChildAssets(assets, 'dashboard').map((a) => a.id)).toEqual([2]);
    });
  });

  describe('descendantAssetIds', () => {
    it('includes files directly in the folder and every nested subfolder, not siblings', () => {
      const assets = [
        asset({ id: 1, folder: 'dashboard' }),
        asset({ id: 2, folder: 'dashboard/specs' }),
        asset({ id: 3, folder: 'dashboard-other' }),
        asset({ id: 4, folder: null }),
      ];
      expect(descendantAssetIds(assets, 'dashboard').sort()).toEqual([1, 2]);
    });
  });

  describe('siblingNames', () => {
    it('combines child folder labels and child file names at a location', () => {
      const paths = buildFolderPaths([], [folder({ path: 'dashboard' })]);
      const assets = [asset({ name: 'readme.md', folder: null })];
      expect(siblingNames(paths, assets, '').sort()).toEqual(['dashboard', 'readme.md']);
    });
  });

  describe('folderItemCount', () => {
    it('counts direct child folders plus direct child files, not deep descendants', () => {
      const paths = buildFolderPaths([], [folder({ path: 'dashboard' }), folder({ path: 'dashboard/specs' })]);
      const assets = [asset({ folder: 'dashboard' }), asset({ id: 2, folder: 'dashboard/specs' })];
      expect(folderItemCount(paths, assets, 'dashboard')).toBe(2); // 1 subfolder + 1 direct file
    });
  });

  describe('searchAssets', () => {
    const assets = [
      asset({ id: 1, name: 'api-spec.md', folder: 'dashboard/specs' }),
      asset({ id: 2, name: 'error-codes.md', folder: 'dashboard/specs' }),
      asset({ id: 3, name: 'readme.md', folder: null }),
    ];

    it('returns everything for a blank query', () => {
      expect(searchAssets(assets, '  ')).toHaveLength(3);
    });

    it('matches by file name, case-insensitively', () => {
      expect(searchAssets(assets, 'README').map((a) => a.id)).toEqual([3]);
    });

    it('matches by the full folder/name path', () => {
      expect(
        searchAssets(assets, 'dashboard/specs')
          .map((a) => a.id)
          .sort(),
      ).toEqual([1, 2]);
    });
  });
});
