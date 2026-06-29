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

// Initialize Sentry before the app mounts so boot-time errors are captured.
// With `use_script_element_for_initial_page`, Inertia serializes the initial
// page into a `<script type="application/json">` element (mirroring its own
// getInitialPageFromDOM) rather than the #app div's data-page attribute, so read
// it from there. Fall back to the div for the legacy attribute mode.
try {
  const pageJson =
    document.querySelector('script[data-page="app"][type="application/json"]')?.textContent ??
    document.getElementById('app')?.dataset.page;
  if (pageJson) {
    const page = JSON.parse(pageJson);
    if (page.props?.settings) {
      initSentry(page.props.settings);
    }
  }
} catch {
  // Sentry init will be skipped if page data is missing or malformed
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
