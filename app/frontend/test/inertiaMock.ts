import { vi } from 'vitest';

/**
 * A controllable stub of Inertia's useForm() return value.
 * NOTE: not reactive — setData mutates the captured object but does not trigger a React
 * re-render. Test the validation-failure branch (submit empty) or pre-seed valid data.
 */
export function makeFormStub<T extends Record<string, unknown>>(initial: T = {} as T) {
  let data: Record<string, unknown> = { ...initial };
  const submit = vi.fn();
  const stub: Record<string, unknown> = {
    data,
    errors: {} as Record<string, string>,
    processing: false,
    setData: vi.fn((keyOrObj: unknown, value?: unknown) => {
      data = typeof keyOrObj === 'string' ? { ...data, [keyOrObj]: value } : { ...data, ...(keyOrObj as object) };
      (stub as { data: unknown }).data = data;
    }),
    transform: vi.fn(),
    reset: vi.fn(),
    clearErrors: vi.fn(),
    setError: vi.fn(),
    recentlySuccessful: false,
    hasErrors: false,
    isDirty: false,
    post: submit,
    get: submit,
    put: submit,
    patch: submit,
    delete: submit,
    submit,
  };
  return stub;
}

/** Mutable state shared between the @inertiajs/react mock (setup.ts) and renderPage(). */
export const inertiaState: { pageProps: Record<string, unknown>; form: ReturnType<typeof makeFormStub> } = {
  pageProps: {},
  form: makeFormStub(),
};
