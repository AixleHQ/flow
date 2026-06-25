import '@testing-library/jest-dom/vitest';

import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';

// ---------------------------------------------------------------------------
// DOM polyfills Mantine 9 needs in jsdom (from Mantine's official Vitest guide).
// ---------------------------------------------------------------------------
const { getComputedStyle } = window;
window.getComputedStyle = (el) => getComputedStyle(el);
window.HTMLElement.prototype.scrollIntoView = () => {};

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
});

Object.defineProperty(document, 'fonts', {
  value: { addEventListener: vi.fn(), removeEventListener: vi.fn() },
});

class ResizeObserverStub {
  observe() {}
  unobserve() {}
  disconnect() {}
}
window.ResizeObserver = ResizeObserverStub as unknown as typeof ResizeObserver;
window.IntersectionObserver = ResizeObserverStub as unknown as typeof IntersectionObserver;

afterEach(() => cleanup());

// ---------------------------------------------------------------------------
// Backend seams — never touch a real backend.
// The @inertiajs/react factory lazily imports the shared state so it does not
// reference top-level variables (which vi.mock hoisting forbids).
// ---------------------------------------------------------------------------
vi.mock('@rails/actioncable', () => ({
  createConsumer: () => ({
    subscriptions: { create: () => ({ unsubscribe: vi.fn() }) },
    disconnect: vi.fn(),
  }),
}));

vi.mock('@inertiajs/react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@inertiajs/react')>();
  const { inertiaState } = await import('./inertiaMock');
  return {
    ...actual, // keep Link/Head/Deferred/types real where they render fine in jsdom
    usePage: () => ({ props: inertiaState.pageProps, url: '/', component: 'Test', version: '1' }),
    useForm: () => inertiaState.form,
    router: {
      visit: vi.fn(),
      post: vi.fn(),
      get: vi.fn(),
      put: vi.fn(),
      patch: vi.fn(),
      delete: vi.fn(),
      reload: vi.fn(),
      replace: vi.fn(),
      cancel: vi.fn(),
      on: vi.fn(() => () => {}), // must return an unsubscribe fn (InertiaRouteIndicator)
    },
    usePoll: () => ({ stop: vi.fn(), start: vi.fn() }),
  };
});
