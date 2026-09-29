import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import * as Sentry from '@sentry/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { AppCrashFallback } from './AppCrashFallback';

function Broken(): never {
  throw new Error('render failed');
}

describe('AppCrashFallback', () => {
  afterEach(() => vi.restoreAllMocks());

  it('replaces a page that throws while rendering, instead of leaving the screen blank', () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});

    renderPage(
      <Sentry.ErrorBoundary fallback={({ resetError }) => <AppCrashFallback resetError={resetError} />}>
        <Broken />
      </Sentry.ErrorBoundary>,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('This page could not be shown');
    expect(screen.getByRole('button', { name: 'Reload the page' })).toBeInTheDocument();
  });

  it('clears itself on the next Inertia visit', () => {
    const resetError = vi.fn();

    renderPage(<AppCrashFallback resetError={resetError} />);

    expect(router.on).toHaveBeenCalledWith('navigate', resetError);
  });
});
