import type { PendingVisit } from '@inertiajs/core';
import { router } from '@inertiajs/react';
import { vi } from 'vitest';

/**
 * Fires the cancelable Inertia `before` event a visit would, at every listener the rendered page
 * registered through the mocked `router.on`. Returns true when one of them held the visit.
 */
export function visitHeld(path: string, visit: Partial<PendingVisit> = {}) {
  const event = new CustomEvent('inertia:before', {
    cancelable: true,
    detail: {
      visit: {
        url: new URL(path, window.location.origin),
        method: 'get',
        prefetch: false,
        only: [],
        except: [],
        headers: {},
        ...visit,
      },
    },
  });
  const listeners = new Set(
    vi
      .mocked(router.on)
      .mock.calls.filter(([name]) => name === 'before')
      .map(([, listener]) => listener as (event: CustomEvent) => void),
  );
  listeners.forEach((listener) => listener(event));
  return event.defaultPrevented;
}
