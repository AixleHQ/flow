import * as Sentry from '@sentry/react';

import type { SharedSettings } from 'shared/ui/types';

export const initSentry = (settings: SharedSettings): void => {
  const { env, appVersion, domain, sentryFrontendDsn } = settings;
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
      Sentry.replayIntegration({ maskAllText: false, blockAllMedia: false }),
    ],
    tracesSampleRate: 1.0,
    tracePropagationTargets: [/^\//, new RegExp(`^https?://${domain}`)],
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,
    sendDefaultPii: true,
    enableLogs: true,
  });
};
