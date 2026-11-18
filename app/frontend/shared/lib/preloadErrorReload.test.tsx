import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent } from 'test/renderPage';

import { registerPreloadErrorReload } from './preloadErrorReload';
import { registerGuard } from './unsaved-changes/guards';

const RELOAD_AT_KEY = 'vitePreloadReloadedAt';

// Dispatch synchronously updates the global Mantine notifications store, which
// re-renders the mounted <Notifications>; wrap it in act() to keep React happy.
const dispatchPreloadError = () => {
  const event = new Event('vite:preloadError', { cancelable: true });
  act(() => {
    window.dispatchEvent(event);
  });
  return event;
};

type VisitListener = (event: { detail: { visit: Record<string, unknown> } }) => void;

const startVisit = (method: string, path: string) => {
  const call = vi
    .mocked(router.on)
    .mock.calls.filter(([type]) => type === 'start')
    .at(-1);
  const listener = call?.[1] as unknown as VisitListener;
  listener({
    detail: { visit: { method, url: new URL(path, window.location.origin), prefetch: false, async: false } },
  });
};

describe('registerPreloadErrorReload', () => {
  let unregister: () => void;
  let reloadSpy: ReturnType<typeof vi.fn>;
  let assignSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    // Notifications live in a global Mantine store; a persistent (autoClose:false)
    // notice from one test would otherwise leak into the next.
    notifications.clean();
    window.sessionStorage.clear();
    reloadSpy = vi.fn();
    assignSpy = vi.fn();
    // jsdom's location.reload is non-configurable via spyOn on some versions;
    // redefine it directly so we can assert it was called.
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { ...window.location, reload: reloadSpy, assign: assignSpy },
    });
  });

  afterEach(() => {
    unregister?.();
    vi.restoreAllMocks();
  });

  it('reloads into the new version and records a guard timestamp', () => {
    unregister = registerPreloadErrorReload();

    const event = dispatchPreloadError();

    expect(event.defaultPrevented).toBe(true);
    expect(reloadSpy).toHaveBeenCalledTimes(1);
    expect(Number(window.sessionStorage.getItem(RELOAD_AT_KEY))).toBeGreaterThan(0);
  });

  it('goes on to the page being visited when the chunk belonged to that visit', () => {
    unregister = registerPreloadErrorReload();

    startVisit('get', '/company/projects/7/board');
    dispatchPreloadError();

    expect(assignSpy).toHaveBeenCalledWith(`${window.location.origin}/company/projects/7/board`);
    expect(reloadSpy).not.toHaveBeenCalled();
  });

  it('reloads in place when the chunk belonged to a form submission', () => {
    unregister = registerPreloadErrorReload();

    startVisit('post', '/login/identify');
    dispatchPreloadError();

    expect(reloadSpy).toHaveBeenCalledTimes(1);
    expect(assignSpy).not.toHaveBeenCalled();
  });

  it('asks first when a form holds unsaved changes', async () => {
    unregister = registerPreloadErrorReload();
    const removeGuard = registerGuard({ dirty: true });

    renderPage(<div />);
    dispatchPreloadError();

    expect(await screen.findByText('New version available')).toBeInTheDocument();
    expect(reloadSpy).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole('button', { name: 'Reload' }));
    expect(reloadSpy).toHaveBeenCalledTimes(1);
    removeGuard();
  });

  it('stops reloading if a chunk still fails right after a reload (loop guard)', async () => {
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now()));
    unregister = registerPreloadErrorReload();

    renderPage(<div />);
    dispatchPreloadError();

    expect(await screen.findByText('Failed to load page')).toBeInTheDocument();
    expect(reloadSpy).not.toHaveBeenCalled();
    expect(assignSpy).not.toHaveBeenCalled();
  });

  it('reloads again for a new deploy once the stale guard flag has aged out', () => {
    // A guard flag older than the window belongs to an earlier, resolved reload.
    window.sessionStorage.setItem(RELOAD_AT_KEY, String(Date.now() - 60_000));
    unregister = registerPreloadErrorReload();

    // Registration clears the aged-out flag so the next deploy is handled fresh.
    expect(window.sessionStorage.getItem(RELOAD_AT_KEY)).toBeNull();

    dispatchPreloadError();

    expect(reloadSpy).toHaveBeenCalledTimes(1);
  });

  it('is idempotent: a second registration does not handle the error twice', () => {
    unregister = registerPreloadErrorReload();
    const secondCleanup = registerPreloadErrorReload();

    dispatchPreloadError();

    expect(reloadSpy).toHaveBeenCalledTimes(1);
    secondCleanup();
  });
});
