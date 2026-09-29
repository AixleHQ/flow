import { describe, expect, it } from 'vitest';

import { scrubUrl } from './sentry';

describe('scrubUrl', () => {
  it('replaces invitation and share-link tokens in the path', () => {
    expect(scrubUrl('https://flow.example.com/invitations/abc.def-123')).toBe(
      'https://flow.example.com/invitations/[token]',
    );
    expect(scrubUrl('/share/s3cr3t/raw')).toBe('/share/[token]/raw');
  });

  it('filters credential-bearing query parameters and keeps the rest', () => {
    expect(scrubUrl('/oauth/callback?code=xyz&state=abc&keep=1')).toBe(
      '/oauth/callback?code=%5Bfiltered%5D&state=%5Bfiltered%5D&keep=1',
    );
  });

  it('leaves ordinary URLs untouched', () => {
    expect(scrubUrl('/company/projects/12/board')).toBe('/company/projects/12/board');
  });
});
