function getCsrfToken(): string {
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
