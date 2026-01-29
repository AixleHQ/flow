import { LinearProgress } from '@mui/material';
import { RouterProvider, createRouter } from '@tanstack/react-router';
import { SnackbarProvider } from 'notistack';
import React from 'react';
import { Provider } from 'react-redux';

import { ThemeProvider } from 'app/providers/ThemeProvider';
import { routeTree } from 'app/routeTree';

import { store } from 'shared/api/store';

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

function App() {
  return (
    <Provider store={store}>
      <ThemeProvider>
        <SnackbarProvider maxSnack={3} anchorOrigin={{ vertical: 'top', horizontal: 'right' }} autoHideDuration={1500}>
          <React.Suspense fallback={<LinearProgress />}>
            <RouterProvider router={router} defaultPreload="intent" defaultPreloadStaleTime={0} />
          </React.Suspense>
        </SnackbarProvider>
      </ThemeProvider>
    </Provider>
  );
}

export default App;
