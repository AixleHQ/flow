import '@testing-library/jest-dom/vitest';
import { http, router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen } from 'test/renderPage';

import { registerInertiaVersionGuard } from './inertiaVersionGuard';

const BOOT = 'digest-old';
const DEPLOYED = 'digest-new';

const listenerFor = (type: string) => {
  const call = vi
    .mocked(router.on)
    .mock.calls.filter(([name]) => name === type)
    .at(-1);
  return call?.[1] as unknown as (event: unknown) => void;
};

const navigateTo = (version: string) => listenerFor('navigate')({ detail: { page: { version } } });

const locationVisit = (path: string, versionChange: boolean) => {
  const event = new CustomEvent('inertia:location', {
    cancelable: true,
    detail: { url: new URL(path, window.location.origin), versionChange },
  });
  act(() => listenerFor('location')(event));
  return event;
};

const visitHeaders = async (headers: Record<string, unknown>) =>
  (await http.processRequest({ method: 'get', url: '/company/projects', headers })).headers;

describe('registerInertiaVersionGuard', () => {
  let unregister: () => void;
  let hrefs: string[];

  beforeEach(() => {
    notifications.clean();
    hrefs = [];
    const location = { ...window.location, href: `${window.location.origin}/company/projects/7/board` };
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: new Proxy(location, {
        set(target, key, value) {
          if (key === 'href') hrefs.push(value);
          return Reflect.set(target, key, value);
        },
      }),
    });
  });

  afterEach(() => {
    unregister?.();
    Reflect.deleteProperty(document, 'visibilityState');
    vi.restoreAllMocks();
  });

  it('sends the version the tab booted with, even after a page from a newer deploy arrived', async () => {
    unregister = registerInertiaVersionGuard(BOOT);
    navigateTo(DEPLOYED);

    expect(await visitHeaders({ 'X-Inertia': true, 'X-Inertia-Version': DEPLOYED })).toEqual({
      'X-Inertia': true,
      'X-Inertia-Version': BOOT,
    });
  });

  it('leaves requests that are not page visits alone', async () => {
    unregister = registerInertiaVersionGuard(BOOT);

    expect(await visitHeaders({ Accept: 'application/json' })).toEqual({ Accept: 'application/json' });
  });

  it('pins nothing when the server sends no version', async () => {
    unregister = registerInertiaVersionGuard(null);

    expect(await visitHeaders({ 'X-Inertia-Version': DEPLOYED })).toEqual({ 'X-Inertia-Version': DEPLOYED });
  });

  it('tells a tab watching a live page that a new version is out instead of freezing it', async () => {
    unregister = registerInertiaVersionGuard(BOOT);
    renderPage(<div />);

    const event = locationVisit('/company/projects/7/board', true);

    expect(event.defaultPrevented).toBe(true);
    expect(await screen.findByText('New version available')).toBeInTheDocument();
    expect(hrefs).toEqual([]);
  });

  it('reloads a tab nobody is looking at', () => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' });
    unregister = registerInertiaVersionGuard(BOOT);

    locationVisit('/company/projects/7/board', true);

    expect(hrefs).toEqual([`${window.location.origin}/company/projects/7/board`]);
  });

  it('opens the page the user was going to with the new version', () => {
    unregister = registerInertiaVersionGuard(BOOT);
    navigateTo(DEPLOYED);

    locationVisit('/company/projects/7/workflows', false);

    expect(hrefs).toEqual([`${window.location.origin}/company/projects/7/workflows`]);
  });

  it('leaves a location visit with no version change to Inertia', () => {
    unregister = registerInertiaVersionGuard(BOOT);

    const event = locationVisit('/company/billing/checkout', false);

    expect(event.defaultPrevented).toBe(false);
    expect(hrefs).toEqual([]);
  });
});
