import * as Sentry from '@sentry/react';

import type { SharedSettings } from 'shared/ui/types';

export const initSentry = (settings: SharedSettings): void => {
  const { sentryFrontendDsn: dsn, env, appVersion, domain } = settings;

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
