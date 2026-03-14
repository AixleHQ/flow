import * as Sentry from '@sentry/react';

export const initSentry = (): void => {
  const dsn = window.Settings.sentryFrontendDsn;
  const env = window.Settings.env;

  if (!dsn || env === 'development') return;

  Sentry.init({
    dsn,
    release: window.Settings.appVersion,
    environment: env,
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({ maskAllText: false, blockAllMedia: false }),
    ],
    tracesSampleRate: 1.0,
    tracePropagationTargets: [/^\//, new RegExp(`^https?://${window.Settings.domain}`)],
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,
    sendDefaultPii: true,
    enableLogs: true,
  });
};
