import * as Sentry from '@sentry/react';

import type { SharedSettings } from 'shared/ui/types';

const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Path segments and query parameters that carry credentials: invitation and
// share-link tokens are the whole secret, and an OAuth callback carries the
// authorization code. An invitation link also names the invitee's email. They
// are replaced before anything leaves the browser.
const TOKEN_PATH = /\/(invitations|share)\/[^/?#]+/g;
const SECRET_QUERY_PARAMS = ['code', 'state', 'token', 'tkn', 'session_key', 'ticket', 'email'];
const PII_NAME_FRAGMENTS = ['forwarded', '-ip', 'remote-', 'via', '-user'];

const scrubQuery = (query: string): string => {
  const params = new URLSearchParams(query);
  SECRET_QUERY_PARAMS.forEach((name) => {
    if (params.has(name)) params.set(name, '[filtered]');
  });
  return params.toString();
};

const scrubPath = (path: string): string => path.replace(TOKEN_PATH, (_match, kind: string) => `/${kind}/[token]`);

export const scrubUrl = (url: string): string => {
  const [beforeHash] = url.split('#');
  const [path, query] = beforeHash.split('?');
  const cleanPath = scrubPath(path);
  return query ? `${cleanPath}?${scrubQuery(query)}` : cleanPath;
};

const carriesSecret = (url: string): boolean => {
  const [beforeHash] = url.split('#');
  const [path, query = ''] = beforeHash.split('?');
  const params = new URLSearchParams(query);
  return scrubPath(path) !== path || SECRET_QUERY_PARAMS.some((name) => params.has(name));
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

const FRAME_URL_KEYS = ['url', 'from', 'to', 'previous'];

export const scrubRecordingEvent = (event: Sentry.ReplayFrameEvent): Sentry.ReplayFrameEvent => {
  if (event.data.tag !== 'breadcrumb' && event.data.tag !== 'performanceSpan') return event;
  const frame = event.data.payload as { op?: string; description?: string; data?: Record<string, unknown> };
  if (typeof frame.description === 'string' && /^(navigation|resource)\./.test(frame.op ?? '')) {
    frame.description = scrubUrl(frame.description);
  }
  const data = frame.data;
  if (data) {
    FRAME_URL_KEYS.forEach((key) => {
      if (typeof data[key] === 'string') data[key] = scrubUrl(data[key] as string);
    });
  }
  return event;
};

type ReplayEventFields = Sentry.Event & { urls?: unknown; segment_names?: unknown };

const scrubUrlList = (list: unknown): unknown =>
  Array.isArray(list) ? list.map((item) => (typeof item === 'string' ? scrubUrl(item) : item)) : list;

export const scrubReplayEvent = <T extends ReplayEventFields>(event: T): T => {
  if (event.type !== 'replay_event') return event;
  scrubEvent(event);
  event.urls = scrubUrlList(event.urls);
  event.segment_names = scrubUrlList(event.segment_names);
  return event;
};

type SentryIntegration = Extract<NonNullable<Sentry.BrowserOptions['integrations']>, unknown[]>[number];

const replayUrlScrubbing = (): SentryIntegration => ({
  name: 'ReplayUrlScrubbing',
  processEvent: (event) => scrubReplayEvent(event),
});

const isPageNotFound = (event: Sentry.ErrorEvent): boolean =>
  event.exception?.values?.some((exception) => exception.value?.startsWith('Page not found: ')) ?? false;

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
      // the agent's terminal and IDE frames are never recorded. The recording's
      // own first frame holds the raw page URL and no hook reaches it, so a page
      // opened on a token link is not recorded at all.
      ...(carriesSecret(window.location.href)
        ? []
        : [
            Sentry.replayIntegration({
              maskAllText: true,
              maskAllInputs: true,
              blockAllMedia: true,
              block: ['iframe'],
              beforeAddRecordingEvent: scrubRecordingEvent,
            }),
            replayUrlScrubbing(),
          ]),
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
    // Bots request arbitrary pages, so the resolver's "Page not found" floods Sentry. A chunk that
    // failed to load also surfaces this way; that failure is reported on its own when it persists.
    beforeSend: (event) => (isPageNotFound(event) ? null : scrubEvent(event)),
    beforeSendSpan: scrubSpan,
  });
};
