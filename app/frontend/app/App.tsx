import { Box, LinearProgress, Typography } from '@mui/material';
import * as Sentry from '@sentry/react';
import { RouterProvider, createRouter } from '@tanstack/react-router';
import { SnackbarProvider } from 'notistack';
import React from 'react';
import { Provider } from 'react-redux';

import { ThemeProvider } from 'app/providers/ThemeProvider';
import { routeTree } from 'app/routeTree';

import { store } from 'shared/api';

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router;
  }
}

const router = createRouter({
  routeTree,
  scrollRestoration: true,
  defaultHashScrollIntoView: { behavior: 'smooth' },
  defaultPendingMs: 300,
  defaultPendingMinMs: 1000,
});

const SentryFallback: Sentry.FallbackRender = ({ error, resetError }) => (
  <Box
    sx={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100vh',
      gap: '16px',
    }}
  >
    <Typography variant="h5">Something went wrong</Typography>
    <Typography variant="body1" color="text.secondary">
      {error instanceof Error ? error.message : 'An unexpected error occurred'}
    </Typography>
    <button onClick={resetError}>Try again</button>
  </Box>
);

const App = () => (
  <Sentry.ErrorBoundary fallback={SentryFallback} showDialog>
    <Provider store={store}>
      <ThemeProvider>
        <SnackbarProvider maxSnack={3} anchorOrigin={{ vertical: 'top', horizontal: 'right' }} autoHideDuration={1500}>
          <React.Suspense fallback={<LinearProgress />}>
            <RouterProvider router={router} defaultPreload="intent" defaultPreloadStaleTime={0} />
          </React.Suspense>
        </SnackbarProvider>
      </ThemeProvider>
    </Provider>
  </Sentry.ErrorBoundary>
);

export default App;
