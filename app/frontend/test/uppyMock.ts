/**
 * Shared state for the inert `@uppy/core` stub installed in `setup.ts`.
 *
 * The stub records the listeners a component registers so a test can drive the upload lifecycle
 * ('complete', 'error', …) without a real S3 round-trip. Kept in its own module because `vi.mock`
 * factories may not reference top-level variables — the factory imports this lazily, exactly like
 * the `@inertiajs/react` mock does with `inertiaMock`.
 */
type UppyListener = (...args: never[]) => void;

export const uppyState: { listeners: Map<string, UppyListener[]> } = { listeners: new Map() };

export function recordUppyListener(event: string, listener: UppyListener): void {
  const existing = uppyState.listeners.get(event) ?? [];
  uppyState.listeners.set(event, [...existing, listener]);
}

export function resetUppyMock(): void {
  uppyState.listeners.clear();
}

/** Invoke every listener a component registered for `event`, as Uppy itself would. */
export function emitUppy(event: string, ...args: unknown[]): void {
  for (const listener of uppyState.listeners.get(event) ?? []) {
    (listener as (...a: unknown[]) => void)(...args);
  }
}
