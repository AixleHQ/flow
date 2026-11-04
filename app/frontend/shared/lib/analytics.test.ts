import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildSharedAnalytics } from 'test/factories/sharedProps';
import { answerFetch } from 'test/fetchStub';

import {
  consentPending,
  effectiveConsent,
  featureArea,
  maskText,
  sanitizeEvent,
  sanitizeRequest,
  setConsent,
  syncAnalytics,
} from './analytics';

type Event = Parameters<typeof sanitizeEvent>[0];

const page = (analytics: ReturnType<typeof buildSharedAnalytics> | null, url = '/company/projects') => ({
  component: 'Projects/IndexPage',
  url,
  props: { analytics },
});

const clearCookie = () => {
  document.cookie = 'analytics_consent=; Path=/; Max-Age=0';
};

afterEach(() => {
  clearCookie();
  vi.unstubAllGlobals();
});

describe('sanitizeEvent', () => {
  it('takes tokens and personal query parameters out of every URL property, and drops the page title', () => {
    const event = {
      event: '$pageview',
      properties: {
        $current_url: 'https://flow.example.com/invitations/s3cr3t?email=dana%40acme.test',
        $pathname: '/login/magic/abc',
        $referrer: 'https://flow.example.com/workspace/confirm?token=t0k',
        title: 'Billing — Acme',
      },
      $set_once: { $initial_current_url: 'https://flow.example.com/password/reset/r3set' },
    } as unknown as Event;

    const clean = sanitizeEvent(event) as unknown as {
      properties: Record<string, unknown>;
      $set_once: Record<string, unknown>;
    };

    expect(clean.properties.$current_url).toBe('https://flow.example.com/invitations/:token');
    expect(clean.properties.$pathname).toBe('/login/magic/:token');
    expect(clean.properties.$referrer).toBe('https://flow.example.com/workspace/confirm');
    expect(clean.properties).not.toHaveProperty('title');
    expect(clean.$set_once.$initial_current_url).toBe('https://flow.example.com/password/reset/:token');
  });
});

describe('sanitizeRequest', () => {
  it('keeps a recorded request to its scrubbed URL, without headers or bodies', () => {
    const request = sanitizeRequest({
      name: 'https://flow.example.com/share/s3cr3t/raw',
      requestHeaders: { authorization: 'Bearer x' },
      responseBody: '{"secret":1}',
    } as unknown as Parameters<typeof sanitizeRequest>[0]);

    expect(request).toEqual({ name: 'https://flow.example.com/share/:token/raw' });
  });
});

describe('maskText', () => {
  it('masks everything outside static navigation', () => {
    const nav = document.createElement('nav');
    nav.setAttribute('data-ph-unmask', '');
    const link = document.createElement('a');
    nav.appendChild(link);
    const cell = document.createElement('td');

    expect(maskText('Board', link)).toBe('Board');
    expect(maskText('Acme Robotics', cell)).toBe('**** ********');
  });
});

describe('featureArea', () => {
  it.each([
    ['Projects/Board/BoardPage', 'board'],
    ['Projects/WorkflowRuns', 'workflows'],
    ['Company/Settings/BillingPage', 'billing'],
    ['Company/Settings/GeneralPage', 'settings'],
    ['Projects/McpServers', 'resources'],
    ['Workspaces/NewPage', 'onboarding'],
    ['Docs/DocsPage', 'docs'],
    ['Projects/IndexPage', 'projects'],
    ['Projects/Overview/OverviewPage', 'projects'],
  ])('puts %s under %s', (component, area) => {
    expect(featureArea(component)).toBe(area);
  });
});

describe('consent', () => {
  it('asks nobody where analytics cannot run at all', () => {
    syncAnalytics(page(null));

    expect(consentPending()).toBe(false);
  });

  it('asks a visitor who has not answered, and stops asking once they decline', async () => {
    syncAnalytics(page(buildSharedAnalytics()));
    expect(consentPending()).toBe(true);

    await setConsent('denied');

    expect(consentPending()).toBe(false);
    expect(document.cookie).toContain('analytics_consent=denied');
  });

  it('keeps a signed-in answer on the account', async () => {
    const save = answerFetch({ 'PATCH /analytics_consent': {} });
    syncAnalytics(page(buildSharedAnalytics({ distinctId: '42' })));

    await setConsent('denied');

    expect(save).toHaveBeenCalledWith('/analytics_consent', expect.objectContaining({ method: 'PATCH' }));
    expect(JSON.parse(String(save.mock.calls[0][1]?.body))).toEqual({ consent: 'denied' });
  });

  it('treats Global Privacy Control as a refusal, without asking', () => {
    vi.stubGlobal('navigator', { ...navigator, globalPrivacyControl: true });

    syncAnalytics(page(buildSharedAnalytics()));

    expect(effectiveConsent()).toBe('denied');
    expect(consentPending()).toBe(false);
    expect(document.cookie).toContain('analytics_consent=denied');
  });
});
