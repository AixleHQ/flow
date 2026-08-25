import '@testing-library/jest-dom/vitest';

import { cleanup } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, vi } from 'vitest';

import { resetUppyMock } from './uppyMock';

interface DeferredStubProps {
  children?: ReactNode;
  data?: string | string[];
  fallback?: ReactNode;
}

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

// CodeMirror (ToolFileEditor) measures text via Range.getClientRects()/getBoundingClientRect(),
// which jsdom does not implement. CM invokes them from a requestAnimationFrame callback, so the
// missing method throws *asynchronously* after the test finishes — an unhandled error that fails the
// whole run even though every test passes. Stub them as empty/zero rects.
Range.prototype.getClientRects = () =>
  ({ length: 0, item: () => null, [Symbol.iterator]: function* () {} }) as unknown as DOMRectList;
Range.prototype.getBoundingClientRect = () =>
  ({ x: 0, y: 0, top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0, toJSON: () => ({}) }) as DOMRect;

// Raw fetch() is a backend seam too. Components such as BuilderPage auto-save via fetch() to RELATIVE
// API URLs (e.g. /api/v1/projects/…/steps/…). jsdom runs on Node's undici fetch, which rejects relative
// URLs ("Failed to parse URL"); a debounced call that fires after its test finished then throws an
// unhandled rejection that contaminates whichever test is running next (a shared-worker, timing-driven
// flake). Default fetch to an inert resolved Response so stray/late calls are harmless; tests that need
// to assert specific requests override this via vi.spyOn(globalThis, 'fetch').
globalThis.fetch = vi.fn(
  async () => new Response('{}', { status: 200, headers: { 'Content-Type': 'application/json' } }),
) as typeof fetch;

afterEach(() => {
  cleanup();
  // Each mounted component registers its Uppy listeners on a fresh instance; drop them so one
  // test's handlers can never be driven by the next.
  resetUppyMock();
});

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

// Uppy + its AwsS3 plugin are the asset-upload seam (AssetsContent presigns to S3). The real
// @uppy/core constructor unconditionally schedules `setTimeout(updateOnlineStatus, 3000)` and
// attaches permanent window 'online'/'offline' listeners that read `window.navigator`. In a worker
// that runs file after file, that 3s timer fires *after* the test's jsdom realm is disposed and
// throws "ReferenceError: window is not defined" as an unhandled error that fails the whole run —
// and only in full runs (>3s), never in isolation (<3s), so it reads as flaky. destroy() removes
// the listeners but cannot cancel the unstored timer. So stub Uppy inert: chainable instance, no
// timers, no window access. Registered listeners are recorded in `uppyMock` so a test can drive the
// upload lifecycle (e.g. emitUppy('complete', …)) without a real S3 round-trip.
vi.mock('@uppy/core', async () => {
  const { recordUppyListener } = await import('./uppyMock');
  class UppyMock {
    use() {
      return this;
    }
    on(event: string, listener: (...args: never[]) => void) {
      recordUppyListener(event, listener);
      return this;
    }
    off() {
      return this;
    }
    addFile() {
      return 'mock-file-id';
    }
    upload() {
      return Promise.resolve({ successful: [], failed: [] });
    }
    cancelAll() {}
    destroy() {}
    close() {}
  }
  return { default: UppyMock };
});

vi.mock('@uppy/aws-s3', () => ({ default: class AwsS3Mock {} }));

vi.mock('@inertiajs/react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@inertiajs/react')>();
  const { inertiaState, resolveForm } = await import('./inertiaMock');
  return {
    ...actual, // keep Link/types real where they render fine in jsdom
    // Inertia's real <Head> reads the head-manager off React context, which the harness never boots,
    // so it throws "Cannot read properties of null (reading 'createProvider')" in jsdom. Pages render
    // <Head> for the document title; stub it inert so every page test renders without a local mock.
    Head: () => null,
    // <Deferred> and <InfiniteScroll> both call usePage() internally and crash in jsdom without a
    // booted Inertia context. Props are injected (not fetched) in tests, so render children directly:
    // Deferred shows children once its data prop(s) are seeded, else the fallback.
    Deferred: ({ children, data, fallback }: DeferredStubProps) => {
      const keys = Array.isArray(data) ? data : data ? [data] : [];
      const ready = keys.every((k) => inertiaState.pageProps[k] !== undefined);
      return ready ? children : (fallback ?? null);
    },
    InfiniteScroll: ({ children }: { children?: ReactNode }) => children ?? null,
    usePage: () => ({ props: inertiaState.pageProps, url: '/', component: 'Test', version: '1' }),
    useForm: (arg1?: unknown, arg2?: unknown) => resolveForm(arg1, arg2),
    router: {
      visit: vi.fn(),
      post: vi.fn(),
      // Resolves its visit's onFinish synchronously so components tracking "request in flight"
      // state (e.g. a loading skeleton keyed off onFinish) don't get stuck mid-test. Args are
      // still recorded on the mock as usual for assertions.
      get: vi.fn((...args: unknown[]) => {
        const options = args[2] as { onFinish?: () => void } | undefined;
        options?.onFinish?.();
      }),
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
