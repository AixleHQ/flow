import { useState } from 'react';

export type AssetViewMode = 'folder' | 'flat';

const STORAGE_KEY = 'aixle.assets.viewMode';

function readStoredMode(): AssetViewMode {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'flat' ? 'flat' : 'folder';
  } catch {
    // Private browsing / storage disabled — fall back to the default view.
    return 'folder';
  }
}

/**
 * View-mode (Folders default / All files) persisted per-viewer across visits; current folder
 * navigation position, which is deliberately NOT persisted — every visit starts back at root.
 */
export function useAssetViewState() {
  const [viewMode, setViewModeState] = useState<AssetViewMode>(readStoredMode);
  const [currentPath, setCurrentPath] = useState('');

  const setViewMode = (mode: AssetViewMode) => {
    setViewModeState(mode);
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {
      /* nothing to persist to — in-memory state for this session still works */
    }
  };

  return { viewMode, setViewMode, currentPath, setCurrentPath };
}
