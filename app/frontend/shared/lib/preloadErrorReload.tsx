import { Button, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';

// After a deploy, hashed Vite chunk filenames change, so an already-loaded SPA
// client that still holds the old index.html gets a 404 when it lazy-loads a
// route chunk (Sentry PALAD-AI-FRONTEND-7). Vite emits a `vite:preloadError`
// event on `window` for exactly this failure. We surface a recoverable prompt
// ("New version available" + Reload) instead of letting the app land on a
// broken page. Reloading fetches the fresh index.html and manifest, resolving
// the mismatch.

// sessionStorage key holding the epoch-ms of our last reload-for-new-version.
const RELOAD_AT_KEY = 'vitePreloadReloadedAt';

// If a chunk still fails within this window after we reloaded, the asset is
// genuinely gone (broken build, or a cache served the same stale index.html) —
// reloading again won't help, so we stop offering it to avoid an endless
// reload/notify loop.
const RELOAD_GUARD_MS = 10_000;

// Stable id so repeated errors update a single notification instead of stacking.
const NOTIFICATION_ID = 'vite-preload-error';

const readReloadedAt = (): number => {
  try {
    return Number(window.sessionStorage.getItem(RELOAD_AT_KEY)) || 0;
  } catch {
    // sessionStorage can throw (private mode / disabled storage); treat as "never".
    return 0;
  }
};

const reloadForNewVersion = (): void => {
  try {
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now()));
  } catch {
    // Storage may be blocked — the reload itself still works, we just lose the
    // loop guard for this one reload.
  }
  window.location.reload();
};

const showNewVersionPrompt = (): void => {
  notifications.show({
    id: NOTIFICATION_ID,
    title: 'New version available',
    message: (
      <Stack gap="xs">
        <Text size="sm">A new version was just deployed. Reload to continue.</Text>
        <Button size="xs" variant="light" onClick={reloadForNewVersion}>
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

const handlePreloadError = (event: Event): void => {
  // Suppress Vite's default behavior of rethrowing the failure as an unhandled
  // rejection; we surface our own recoverable prompt instead.
  event.preventDefault();

  const reloadedAt = readReloadedAt();
  if (reloadedAt && Date.now() - reloadedAt < RELOAD_GUARD_MS) {
    // We already reloaded very recently and it still failed — don't loop.
    showLoadFailedPrompt();
    return;
  }

  showNewVersionPrompt();
};

let registered = false;

/**
 * Register the global `vite:preloadError` handler. Idempotent — calling it more
 * than once is a no-op. Returns a cleanup function that removes the listener.
 */
export const registerPreloadErrorReload = (): (() => void) => {
  if (registered) return () => {};
  registered = true;

  // A stale guard flag left over from an earlier (now-succeeded) reload must not
  // suppress the prompt for a genuinely new deploy later in the session. Clear
  // it once it falls outside the guard window.
  const reloadedAt = readReloadedAt();
  if (reloadedAt && Date.now() - reloadedAt >= RELOAD_GUARD_MS) {
    try {
      window.sessionStorage.removeItem(RELOAD_AT_KEY);
    } catch {
      // ignore — a stale flag at worst suppresses one prompt.
    }
  }

  window.addEventListener('vite:preloadError', handlePreloadError);
  return () => {
    window.removeEventListener('vite:preloadError', handlePreloadError);
    registered = false;
  };
};
