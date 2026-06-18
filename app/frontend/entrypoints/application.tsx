import { createInertiaApp } from '@inertiajs/react';
import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import * as Sentry from '@sentry/react';

import { initSentry } from 'shared/lib/sentry';
import { cssVariablesResolver, mantineTheme } from 'shared/theme/mantineTheme';
import { InertiaRouteIndicator } from 'shared/ui';

import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import '@mantine/dates/styles.css';
import './global.css';

const appEl = document.getElementById('app');
if (appEl?.dataset.page) {
  try {
    const page = JSON.parse(appEl.dataset.page);
    if (page.props?.settings) {
      initSentry(page.props.settings);
    }
  } catch {
    // Sentry init will be skipped if page data is malformed
  }
}

createInertiaApp({
  strictMode: true,

  pages: {
    path: '../pages',
    extension: '.tsx',
    lazy: true,
  },

  withApp(app: React.ReactNode) {
    return (
      <Sentry.ErrorBoundary showDialog>
        <MantineProvider theme={mantineTheme} defaultColorScheme="dark" cssVariablesResolver={cssVariablesResolver}>
          <ModalsProvider>
            <Notifications position="top-right" />
            <InertiaRouteIndicator />
            {app}
          </ModalsProvider>
        </MantineProvider>
      </Sentry.ErrorBoundary>
    );
  },
});
