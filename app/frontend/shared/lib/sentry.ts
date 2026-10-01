import * as Sentry from '@sentry/react';

import type { SharedSettings } from 'shared/ui/types';

const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Path segments and query parameters that carry credentials: invitation and
// share-link tokens are the whole secret, and an OAuth callback carries the
// authorization code. They are replaced before anything leaves the browser.
const TOKEN_PATH = /\/(invitations|share)\/[^/?#]+/g;
const SECRET_QUERY_PARAMS = ['code', 'state', 'token', 'tkn', 'session_key', 'ticket'];
const PII_NAME_FRAGMENTS = ['forwarded', '-ip', 'remote-', 'via', '-user'];

const scrubQuery = (query: string): string => {
  const params = new URLSearchParams(query);
  SECRET_QUERY_PARAMS.forEach((name) => {
    if (params.has(name)) params.set(name, '[filtered]');
  });
  return params.toString();
};

export const scrubUrl = (url: string): string => {
  const [beforeHash] = url.split('#');
  const [path, query] = beforeHash.split('?');
  const cleanPath = path.replace(TOKEN_PATH, (_match, kind: string) => `/${kind}/[token]`);
  return query ? `${cleanPath}?${scrubQuery(query)}` : cleanPath;
};

type StreamedSpan = Parameters<NonNullable<Sentry.BrowserOptions['beforeSendSpan']>>[0];

// `url.query` holds a bare query string, which scrubUrl would read as a path.
const scrubUrlAttribute = (key: string, value: string): string =>
  key === 'url.query' ? scrubQuery(value) : scrubUrl(value);

const isStringAttribute = (attribute: unknown): attribute is { value: string } =>
  typeof attribute === 'object' && attribute !== null && typeof (attribute as { value?: unknown }).value === 'string';

const scrubSpan = (span: StreamedSpan): StreamedSpan => {
  span.name = scrubUrl(span.name);
  Object.entries(span.attributes).forEach(([key, attribute]) => {
    if (!key.startsWith('url.') && key !== 'sentry.segment.name') return;
    if (typeof attribute === 'string') {
      span.attributes[key] = scrubUrlAttribute(key, attribute);
    } else if (isStringAttribute(attribute)) {
      attribute.value = scrubUrlAttribute(key, attribute.value);
    }
  });
  return span;
};

const scrubEvent = <T extends Sentry.Event>(event: T): T => {
  if (event.request?.url) event.request.url = scrubUrl(event.request.url);
  if (typeof event.transaction === 'string') event.transaction = scrubUrl(event.transaction);
  event.breadcrumbs?.forEach((crumb) => {
    const data = crumb.data as Record<string, unknown> | undefined;
    if (!data) return;
    ['url', 'from', 'to'].forEach((key) => {
      if (typeof data[key] === 'string') data[key] = scrubUrl(data[key] as string);
    });
  });
  return event;
};

export const initSentry = (settings: SharedSettings): void => {
  const { env, appVersion, domain, sentryFrontendDsn, sentryTracesSampleRate } = settings;
  // A browser Sentry DSN is public by design (write-only ingest for one project),
  // so it rides in shared props — runtime-configurable via ENV, no rebuild needed.
  const dsn = sentryFrontendDsn ?? undefined;

  if (!dsn || env === 'development') return;

  Sentry.init({
    dsn,
    release: appVersion ?? undefined,
    environment: env,
    integrations: [
      Sentry.browserTracingIntegration(),
      // A replay records what the page shows — a personal MCP token displayed
      // once, config values, agent output — so text and inputs are masked, and
      // the agent's terminal and IDE frames are never recorded.
      Sentry.replayIntegration({ maskAllText: true, maskAllInputs: true, blockAllMedia: true, block: ['iframe'] }),
    ],
    tracesSampleRate: sentryTracesSampleRate ?? 1.0,
    tracePropagationTargets: [/^\//, new RegExp(`^https?://${escapeRegExp(domain)}(?=[/:?#]|$)`)],
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,
    // Unset, Sentry 11 collects user info, cookies, headers and bodies. This is the
    // `sendDefaultPii: false` baseline of Sentry 10, as its migration guide spells it out.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: { request: { deny: PII_NAME_FRAGMENTS }, response: { deny: PII_NAME_FRAGMENTS } },
      httpBodies: [],
      urlQueryParams: { deny: PII_NAME_FRAGMENTS },
      genAI: { inputs: false, outputs: false },
      databaseQueryData: false,
      queues: false,
      graphQL: { document: false, variables: false },
    },
    beforeSend: (event) => scrubEvent(event),
    beforeSendSpan: scrubSpan,
  });
};
