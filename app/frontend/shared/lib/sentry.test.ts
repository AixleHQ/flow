import * as Sentry from '@sentry/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import type { SharedSettings } from 'shared/ui/types';

import { registerPreloadErrorReload } from './preloadErrorReload';
import { initSentry, scrubRecordingEvent, scrubReplayEvent, scrubUrl } from './sentry';

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

  it('filters an email address carried in the query', () => {
    expect(scrubUrl('/invitations/abc?email=jane%40example.com')).toBe('/invitations/[token]?email=%5Bfiltered%5D');
  });
});

describe('scrubRecordingEvent', () => {
  it('scrubs the URLs a replay records for navigations and requests', () => {
    const navigation = scrubRecordingEvent({
      type: 5,
      timestamp: 1,
      data: {
        tag: 'breadcrumb',
        payload: {
          timestamp: 1,
          type: 'default',
          category: 'navigation',
          data: { from: '/company/projects', to: '/share/s3cr3t?token=t0k' },
        },
      },
    });
    const pageLoad = scrubRecordingEvent({
      type: 5,
      timestamp: 1,
      data: {
        tag: 'performanceSpan',
        payload: {
          op: 'navigation.navigate',
          description: 'https://flow.example.com/invitations/s3cr3t?email=a%40b.c',
          startTimestamp: 1,
          endTimestamp: 2,
          data: { previous: '/oauth/callback?code=c0de_secret' },
        },
      },
    });

    expect(JSON.stringify([navigation, pageLoad])).not.toMatch(/s3cr3t|t0k|c0de_secret|a%40b/);
    expect(JSON.stringify(pageLoad)).toContain('https://flow.example.com/invitations/[token]');
  });
});

describe('scrubReplayEvent', () => {
  it('scrubs the URLs listed on a replay', () => {
    const event = scrubReplayEvent({
      type: 'replay_event',
      urls: ['https://flow.example.com/invitations/s3cr3t?email=a%40b.c'],
      request: { url: 'https://flow.example.com/share/s3cr3t' },
    });

    expect(event.urls).toEqual(['https://flow.example.com/invitations/[token]?email=%5Bfiltered%5D']);
    expect(event.request?.url).toBe('https://flow.example.com/share/[token]');
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
    window.history.replaceState({}, '', '/invitations/s3cr3t?code=c0de_secret');
    initSentry(settings);

    Sentry.captureException(new Error('boom'));
    Sentry.getActiveSpan()?.end();
    await Sentry.flush(2000);

    const envelopes = sent.join('\n');
    expect(envelopes).toContain('"type":"event"');
    expect(envelopes).toContain('"type":"span"');
    expect(envelopes).toContain('/invitations/[token]?code=%5Bfiltered%5D');
    expect(envelopes).toContain('"infer_ip":"never"');
    expect(envelopes).not.toMatch(/s3cr3t|c0de_secret/);
  });

  it('records no replay of a page opened on a token link', () => {
    window.history.replaceState({}, '', '/invitations/s3cr3t');
    initSentry(settings);

    expect(Sentry.getClient()?.getIntegrationByName('Replay')).toBeUndefined();
  });

  it('records replays of ordinary pages', () => {
    window.history.replaceState({}, '', '/company/projects');
    initSentry(settings);

    expect(Sentry.getClient()?.getIntegrationByName('Replay')).toBeDefined();
  });

  describe('a chunk that fails to load', () => {
    let unregister: () => void;

    afterEach(() => {
      unregister?.();
      window.sessionStorage.clear();
    });

    it('reports a page as missing only when no chunk failed before it', async () => {
      const sent: string[] = [];
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (_input, init) => {
        sent.push(String(init?.body));
        return new Response('{}');
      });
      initSentry(settings);
      unregister = registerPreloadErrorReload();

      Sentry.captureException(new Error('Page not found: Projects/Settings/Gone'));
      // Reloaded a moment ago and the chunk still fails: the guard stops reloading and reports it.
      window.sessionStorage.setItem('vitePreloadReloadedAt', String(Date.now()));
      window.dispatchEvent(
        Object.assign(new Event('vite:preloadError', { cancelable: true }), {
          payload: new Error('Failed to fetch dynamically imported module: /vite/assets/SettingsPage-abc.js'),
        }),
      );
      Sentry.captureException(new Error('Page not found: Company/Settings/SettingsPage'));
      await Sentry.flush(2000);

      const envelopes = sent.join('\n');
      expect(envelopes).toContain('Page not found: Projects/Settings/Gone');
      expect(envelopes).not.toContain('Page not found: Company/Settings/SettingsPage');
      expect(envelopes).toContain('A page chunk still failed to load after a reload');
      expect(envelopes).toContain('SettingsPage-abc.js');
    });
  });
});
