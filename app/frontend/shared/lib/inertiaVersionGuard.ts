import { http, router } from '@inertiajs/react';

import { showNewVersionPrompt } from './preloadErrorReload';

const withoutHash = (href: string) => href.split('#')[0];

/**
 * Keeps a tab on the bundle it booted with honest about it. Inertia sends the
 * version of the last page it received, and a page rendered for a POST arrives
 * with the new deploy's version, so the old bundle would pass every later GET's
 * version check and fetch chunks the new deploy no longer serves. Pinning the
 * header to the boot version makes the server answer 409 and the tab reload.
 *
 * A 409 to a background (async) request is dropped by Inertia, which leaves a
 * live-updating page frozen without a word. The tab is told instead, or
 * reloaded while nobody is looking at it.
 */
export const registerInertiaVersionGuard = (bootVersion: string | null | undefined): (() => void) => {
  if (!bootVersion) return () => {};

  let pageVersion: string | null | undefined = bootVersion;

  const removePin = http.onRequest((config) => {
    const headers = config.headers ?? {};
    const name = Object.keys(headers).find((key) => key.toLowerCase() === 'x-inertia-version');
    if (!name) return config;
    return { ...config, headers: { ...headers, [name]: bootVersion } };
  });

  const removeNavigate = router.on('navigate', (event) => {
    pageVersion = event.detail.page.version;
  });

  const removeLocation = router.on('location', (event) => {
    const { url, versionChange } = event.detail;
    if (!versionChange && pageVersion === bootVersion) return;

    event.preventDefault();
    const reloadsThisPage = withoutHash(url.href) === withoutHash(window.location.href);
    if (!reloadsThisPage || document.visibilityState === 'hidden') {
      window.location.href = url.href;
      return;
    }
    showNewVersionPrompt();
  });

  return () => {
    removePin();
    removeNavigate();
    removeLocation();
  };
};
