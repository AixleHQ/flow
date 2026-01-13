import { LinearProgress } from '@mui/material';
import { RouterProvider, createRouter } from '@tanstack/react-router';
import React from 'react';

import { ThemeProvider } from 'app/providers/ThemeProvider';
import { routeTree } from 'app/routeTree';

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
    <ThemeProvider>
      <React.Suspense fallback={<LinearProgress />}>
        <RouterProvider router={router} defaultPreload="intent" defaultPreloadStaleTime={0} />
      </React.Suspense>
    </ThemeProvider>
  );
}

export default App;
