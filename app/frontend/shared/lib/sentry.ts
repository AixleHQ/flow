import * as Sentry from '@sentry/react';

import type { SharedSettings } from 'shared/ui/types';

const escapeRegExp = (value: string): string => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Path segments and query parameters that carry credentials: invitation and
// share-link tokens are the whole secret, and an OAuth callback carries the
// authorization code. They are replaced before anything leaves the browser.
const TOKEN_PATH = /\/(invitations|share)\/[^/?#]+/g;
const SECRET_QUERY_PARAMS = ['code', 'state', 'token', 'tkn', 'session_key', 'ticket'];

export const scrubUrl = (url: string): string => {
  const [beforeHash] = url.split('#');
  const [path, query] = beforeHash.split('?');
  const cleanPath = path.replace(TOKEN_PATH, (_match, kind: string) => `/${kind}/[token]`);
  if (!query) return cleanPath;

  const params = new URLSearchParams(query);
  SECRET_QUERY_PARAMS.forEach((name) => {
    if (params.has(name)) params.set(name, '[filtered]');
  });
  return `${cleanPath}?${params.toString()}`;
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
    sendDefaultPii: false,
    beforeSend: (event) => scrubEvent(event),
    beforeSendTransaction: (event) => scrubEvent(event),
  });
};
