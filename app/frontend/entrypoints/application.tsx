import * as Sentry from '@sentry/react';
import * as React from 'react';
import { createRoot } from 'react-dom/client';

import App from 'app/App.tsx';

import { initSentry } from 'shared/lib/sentry';

initSentry();

createRoot(document.getElementById('root')!, {
  onUncaughtError: Sentry.reactErrorHandler(),
  onCaughtError: Sentry.reactErrorHandler(),
  onRecoverableError: Sentry.reactErrorHandler(),
}).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
