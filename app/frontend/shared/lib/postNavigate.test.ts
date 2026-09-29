import { afterEach, describe, expect, it, vi } from 'vitest';

import { postNavigate } from './postNavigate';

describe('postNavigate', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    document.head.innerHTML = '';
    document.body.innerHTML = '';
  });

  it('submits a hidden POST form carrying the CSRF token and the given params', () => {
    document.head.innerHTML = '<meta name="csrf-token" content="token-123">';
    // jsdom does not navigate on form submission; the submitted form is what matters.
    const submit = vi.spyOn(HTMLFormElement.prototype, 'submit').mockImplementation(() => {});

    postNavigate('/oauth/mcp/7/connect', { return_to: '/projects/1/mcp_servers' });

    expect(submit).toHaveBeenCalledTimes(1);
    const form = submit.mock.contexts[0] as HTMLFormElement;
    const data = new FormData(form);
    expect(form.method).toBe('post');
    expect(form.getAttribute('action')).toBe('/oauth/mcp/7/connect');
    expect(data.get('authenticity_token')).toBe('token-123');
    expect(data.get('return_to')).toBe('/projects/1/mcp_servers');
  });
});
