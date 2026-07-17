import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { registerPreloadErrorReload } from './preloadErrorReload';

const RELOAD_AT_KEY = 'vitePreloadReloadedAt';

// Dispatch synchronously updates the global Mantine notifications store, which
// re-renders the mounted <Notifications>; wrap it in act() to keep React happy.
const dispatchPreloadError = () =>
  act(() => {
    window.dispatchEvent(new Event('vite:preloadError', { cancelable: true }));
  });

describe('registerPreloadErrorReload', () => {
  let unregister: () => void;
  let reloadSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    // Notifications live in a global Mantine store; a persistent (autoClose:false)
    // notice from one test would otherwise leak into the next.
    notifications.clean();
    window.sessionStorage.clear();
    reloadSpy = vi.fn();
    // jsdom's location.reload is non-configurable via spyOn on some versions;
    // redefine it directly so we can assert it was called.
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { ...window.location, reload: reloadSpy },
    });
  });

  afterEach(() => {
    unregister?.();
    vi.restoreAllMocks();
  });

  it('shows a "New version available" reload prompt on vite:preloadError', async () => {
    unregister = registerPreloadErrorReload();

    // Mount the Mantine notifications container so shown notices render to the DOM.
    renderPage(<div />);
    dispatchPreloadError();

    expect(await screen.findByText('New version available')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reload' })).toBeInTheDocument();
  });

  it('reloads the page and records a guard timestamp when Reload is pressed', async () => {
    unregister = registerPreloadErrorReload();

    renderPage(<div />);
    dispatchPreloadError();

    const button = await screen.findByRole('button', { name: 'Reload' });
    await userEvent.click(button);

    expect(reloadSpy).toHaveBeenCalledTimes(1);
    expect(Number(window.sessionStorage.getItem(RELOAD_AT_KEY))).toBeGreaterThan(0);
  });

  it('calls preventDefault so Vite does not rethrow the error as an unhandled rejection', () => {
    unregister = registerPreloadErrorReload();

    const event = new Event('vite:preloadError', { cancelable: true });
    window.dispatchEvent(event);

    expect(event.defaultPrevented).toBe(true);
  });

  it('does not offer another reload if a chunk still fails right after a reload (loop guard)', async () => {
    // Simulate that we reloaded a moment ago and the chunk STILL fails.
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now()));
    unregister = registerPreloadErrorReload();

    renderPage(<div />);
    dispatchPreloadError();

    expect(await screen.findByText('Failed to load page')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Reload' })).not.toBeInTheDocument();
  });

  it('offers a reload again for a new deploy once the stale guard flag has aged out', async () => {
    // A guard flag older than the window belongs to an earlier, resolved reload.
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now() - 60_000));
    unregister = registerPreloadErrorReload();

    // Registration clears the aged-out flag so the next deploy is handled fresh.
    expect(window.sessionStorage.getItem(RELOAD_AT_KEY)).toBeNull();

    renderPage(<div />);
    dispatchPreloadError();

    expect(await screen.findByText('New version available')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reload' })).toBeInTheDocument();
  });

  it('is idempotent: a second registration does not stack a second prompt', async () => {
    unregister = registerPreloadErrorReload();
    const secondCleanup = registerPreloadErrorReload();

    const showSpy = vi.spyOn(notifications, 'show');
    renderPage(<div />);
    dispatchPreloadError();

    await waitFor(() => expect(showSpy).toHaveBeenCalledTimes(1));

    secondCleanup();
  });
});
