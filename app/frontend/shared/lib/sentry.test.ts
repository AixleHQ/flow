import * as Sentry from '@sentry/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { SharedSettings } from 'shared/ui/types';

import { initSentry, scrubUrl } from './sentry';

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

describe('initSentry', () => {
  const settings: SharedSettings = {
    env: 'production',
    domain: 'flow.example.com',
    githubAppSlug: null,
    appVersion: 'test',
    sentryFrontendDsn: 'https://public@o1.ingest.sentry.io/1',
  };

  afterEach(async () => {
    await Sentry.getClient()?.close();
    window.history.replaceState({}, '', '/');
  });

  it('keeps credentials out of the errors and spans it sends, and does not infer the IP', async () => {
    const sent: string[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
      sent.push(String(init?.body));
      return new Response('{}');
    });
    window.history.replaceState({}, '', '/invitations/s3cr3t?code=c0de');
    initSentry(settings);

    Sentry.captureException(new Error('boom'));
    Sentry.getActiveSpan()?.end();
    await Sentry.flush(2000);

    const envelopes = sent.join('\n');
    expect(envelopes).toContain('"type":"event"');
    expect(envelopes).toContain('"type":"span"');
    expect(envelopes).toContain('/invitations/[token]?code=%5Bfiltered%5D');
    expect(envelopes).toContain('"infer_ip":"never"');
    expect(envelopes).not.toMatch(/s3cr3t|c0de/);
  });
});
