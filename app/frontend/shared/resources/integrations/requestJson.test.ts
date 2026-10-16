import { afterEach, describe, expect, it, vi } from 'vitest';

import { requestJson } from './requestJson';

describe('requestJson', () => {
  afterEach(() => {
    document.cookie = 'XSRF-TOKEN=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
    document.head.innerHTML = '';
    vi.unstubAllGlobals();
  });

  // Signing in without a page load (the Bitbucket connect page does) resets the
  // session and its token; only the cookie follows it, the meta tag is stale.
  it('sends the token from the XSRF-TOKEN cookie over a stale meta tag', async () => {
    document.head.innerHTML = '<meta name="csrf-token" content="stale">';
    document.cookie = 'XSRF-TOKEN=fresh%3D%3D; path=/';
    const fetchMock = vi.fn().mockResolvedValue(new Response('{"ok":true}', { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await requestJson('/x', { method: 'POST', body: '{}' });

    const headers = fetchMock.mock.calls[0][1].headers as Record<string, string>;
    expect(headers['X-CSRF-Token']).toBe('fresh==');
  });

  it('throws the server message on a refusal', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{"message":"Nope"}', { status: 422 })));

    await expect(requestJson('/x')).rejects.toThrow('Nope');
  });
});
