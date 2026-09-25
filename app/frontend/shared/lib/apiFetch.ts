import { notifications } from '@mantine/notifications';

// The XSRF-TOKEN cookie is rewritten on every page response (inertia_rails), so it
// follows the session through a sign-in that happened without a page load — which
// resets the session and its token. The meta tag is only as fresh as the last full load.
export function getCsrfToken(): string {
  const cookie = document.cookie.split('; ').find((entry) => entry.startsWith('XSRF-TOKEN='));
  if (cookie) return decodeURIComponent(cookie.slice('XSRF-TOKEN='.length));

  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

/**
 * Wrapper around `fetch` that automatically injects the CSRF token,
 * credentials, and JSON Accept header for Rails API calls.
 */
export function apiFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const headers = new Headers(init?.headers);

  if (!headers.has('X-CSRF-Token')) {
    headers.set('X-CSRF-Token', getCsrfToken());
  }
  if (!headers.has('Accept')) {
    headers.set('Accept', 'application/json');
  }

  return fetch(input, {
    ...init,
    credentials: init?.credentials ?? 'include',
    headers,
  });
}

/** A non-2xx answer: `message` is the server's own explanation when it gave one. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly body: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

async function readBody(res: Response): Promise<unknown> {
  if (res.status === 204) return undefined;
  const text = await res.text();
  if (!text) return undefined;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function serverMessage(body: unknown): string | null {
  if (body && typeof body === 'object') {
    const { error, message, errors } = body as { error?: unknown; message?: unknown; errors?: unknown };
    for (const candidate of [message, error]) if (typeof candidate === 'string' && candidate) return candidate;
    if (Array.isArray(errors) && errors.length > 0) return errors.map(String).join(', ');
  }
  return null;
}

/** The ApiError for a non-2xx answer; reads its body. */
export async function toApiError(res: Response): Promise<ApiError> {
  const body = await readBody(res);
  return new ApiError(res.status, serverMessage(body) ?? `Request failed (${res.status})`, body);
}

/**
 * `apiFetch` that fails loudly: resolves with the parsed body of a 2xx answer and
 * throws an ApiError for anything else, so a caller cannot mistake a refusal for
 * a success by forgetting to look at `res.ok`.
 */
export async function apiRequest<T = unknown>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const res = await apiFetch(input, init);
  if (!res.ok) throw await toApiError(res);

  return (await readBody(res)) as T;
}

/**
 * For a change the UI has already shown as made: the request, and on failure a
 * toast with the server's reason. Resolves false so the caller can put the old
 * value back.
 */
export async function apiMutate(
  input: RequestInfo | URL,
  init?: RequestInit,
  failure = 'The change was not saved',
): Promise<boolean> {
  try {
    await apiRequest(input, init);
    return true;
  } catch (error) {
    notifyApiFailure(error, failure);
    return false;
  }
}

/** The toast for a request that failed: the server's reason, or `fallback` when there is none. */
export function notifyApiFailure(error: unknown, fallback: string): void {
  notifications.show({ color: 'red', message: error instanceof ApiError ? error.message : fallback });
}
