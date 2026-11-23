import { router } from '@inertiajs/react';
import { Button, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import * as Sentry from '@sentry/react';

import { hasUnsavedChanges } from 'shared/lib/unsaved-changes/guards';

// After a deploy, hashed Vite chunk filenames change, so an already-loaded SPA
// client that still holds the old index.html gets a 404 when it lazy-loads a
// route chunk (Sentry PALAD-AI-FRONTEND-7). Vite emits a `vite:preloadError`
// event on `window` for exactly this failure. We reload into the new version —
// to the page the user was going to, when a visit was under way — or, with a
// form holding unsaved changes, ask first.

// sessionStorage key holding the epoch-ms of our last reload-for-new-version.
const RELOAD_AT_KEY = 'vitePreloadReloadedAt';

// If a chunk still fails within this window after we reloaded, the asset is
// genuinely gone (broken build, or a cache served the same stale index.html) —
// reloading again won't help, so we stop to avoid an endless reload loop.
const RELOAD_GUARD_MS = 10_000;

// Stable id so repeated errors update a single notification instead of stacking.
const NOTIFICATION_ID = 'vite-preload-error';

let pendingVisitUrl: string | null = null;
let chunkFailed = false;
let reportedStuck = false;

const readReloadedAt = (): number => {
  try {
    return Number(window.sessionStorage.getItem(RELOAD_AT_KEY)) || 0;
  } catch {
    // sessionStorage can throw (private mode / disabled storage); treat as "never".
    return 0;
  }
};

export const reloadForNewVersion = (url?: string | null): void => {
  try {
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now()));
  } catch {
    // Storage may be blocked — the reload itself still works, we just lose the
    // loop guard for this one reload.
  }
  if (url && url !== window.location.href) window.location.assign(url);
  else window.location.reload();
};

export const showNewVersionPrompt = (): void => {
  notifications.show({
    id: NOTIFICATION_ID,
    title: 'New version available',
    message: (
      <Stack gap="xs">
        <Text size="sm">A new version was just deployed. Reload to continue.</Text>
        <Button size="xs" variant="light" onClick={() => reloadForNewVersion()}>
          Reload
        </Button>
      </Stack>
    ),
    color: 'blue',
    autoClose: false,
    withCloseButton: true,
  });
};

const showLoadFailedPrompt = (): void => {
  notifications.show({
    id: NOTIFICATION_ID,
    title: 'Failed to load page',
    message: 'A resource could not be loaded. Please try again in a moment.',
    color: 'red',
    autoClose: 8000,
  });
};

const PROBE_TIMEOUT_MS = 3000;

// Chrome words the failure "Failed to fetch dynamically imported module: <url>";
// other browsers differ, so an empty result means "unknown", never a control-flow input.
const parseChunkUrl = (message: string): string => message.match(/https?:\/\/[^\s'")]+/)?.[0] ?? '';

const chunkHost = (chunkUrl: string): 'own' | 'asset_host' | 'unknown' => {
  if (!chunkUrl) return 'unknown';
  try {
    return new URL(chunkUrl).origin === window.location.origin ? 'own' : 'asset_host';
  } catch {
    return 'unknown';
  }
};

// 404 means the asset is gone; another status or a network error points at transport or cache.
const probeChunk = async (chunkUrl: string): Promise<string> => {
  if (!chunkUrl) return 'unknown';
  try {
    const response = await fetch(chunkUrl, {
      method: 'HEAD',
      cache: 'no-store',
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
    return String(response.status);
  } catch {
    return 'unknown';
  }
};

const reportStuckChunk = async (payload: unknown, reloadedAt: number): Promise<void> => {
  if (reportedStuck) return;
  reportedStuck = true;
  const error = payload instanceof Error ? payload.message : String(payload);
  const chunkUrl = parseChunkUrl(error);
  const chunkStatus = await probeChunk(chunkUrl);
  Sentry.captureMessage('A page chunk still failed to load after a reload', {
    level: 'warning',
    fingerprint: ['stuck-page-chunk'],
    tags: { chunk_host: chunkHost(chunkUrl), reload_age_ms: String(Date.now() - reloadedAt) },
    extra: { error, chunkUrl, chunkStatus },
  });
};

const handlePreloadError = (event: Event): void => {
  // Suppress Vite's default behavior of rethrowing the failure as an unhandled
  // rejection; we recover (or report) ourselves.
  event.preventDefault();
  chunkFailed = true;

  const reloadedAt = readReloadedAt();
  if (reloadedAt && Date.now() - reloadedAt < RELOAD_GUARD_MS) {
    showLoadFailedPrompt();
    void reportStuckChunk((event as Event & { payload?: unknown }).payload, reloadedAt);
    return;
  }

  if (hasUnsavedChanges()) {
    showNewVersionPrompt();
    return;
  }

  reloadForNewVersion(pendingVisitUrl);
};

/**
 * Whether a chunk failed to load in this page's lifetime. The page resolver then
 * fails with "Page not found" for a component that does exist.
 */
export const chunkLoadFailed = (): boolean => chunkFailed;

let registered = false;

/**
 * Register the global `vite:preloadError` handler. Idempotent — calling it more
 * than once is a no-op. Returns a cleanup function that removes the listener.
 */
export const registerPreloadErrorReload = (): (() => void) => {
  if (registered) return () => {};
  registered = true;

  // A stale guard flag left over from an earlier (now-succeeded) reload must not
  // suppress the reload for a genuinely new deploy later in the session. Clear
  // it once it falls outside the guard window.
  const reloadedAt = readReloadedAt();
  if (reloadedAt && Date.now() - reloadedAt >= RELOAD_GUARD_MS) {
    try {
      window.sessionStorage.removeItem(RELOAD_AT_KEY);
    } catch {
      // ignore — a stale flag at worst suppresses one reload.
    }
  }

  const removeStart = router.on('start', (event) => {
    const { visit } = event.detail;
    if (visit.prefetch || visit.async) return;
    pendingVisitUrl = visit.method === 'get' ? visit.url.href : null;
  });
  const removeFinish = router.on('finish', (event) => {
    const { visit } = event.detail;
    if (!visit.prefetch && !visit.async) pendingVisitUrl = null;
  });

  window.addEventListener('vite:preloadError', handlePreloadError);
  return () => {
    window.removeEventListener('vite:preloadError', handlePreloadError);
    removeStart();
    removeFinish();
    pendingVisitUrl = null;
    chunkFailed = false;
    reportedStuck = false;
    registered = false;
  };
};
