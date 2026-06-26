import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { describe, it, expect, vi } from 'vitest';

import { renderPage, screen, act } from 'test/renderPage';

import { InertiaRouteIndicator } from './InertiaRouteIndicator';

/**
 * The harness mocks router.on as vi.fn(() => () => {}) — it records the listener
 * but never fires it. To drive the loading state we capture the callback that the
 * component registered for a given Inertia event and invoke it ourselves.
 */
const fireRouterEvent = (event: 'start' | 'finish') => {
  const call = vi.mocked(router.on).mock.calls.find(([name]) => name === event);
  if (!call) throw new Error(`router.on('${event}') was never registered`);
  const handler = call[1] as () => void;
  act(() => handler());
};

describe('InertiaRouteIndicator', () => {
  it('renders no progress bar while idle', () => {
    renderPage(<InertiaRouteIndicator />);

    expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();
  });

  it('subscribes to the start and finish navigation events on mount', () => {
    renderPage(<InertiaRouteIndicator />);

    const events = vi.mocked(router.on).mock.calls.map(([name]) => name);
    expect(events).toContain('start');
    expect(events).toContain('finish');
  });

  it('shows the progress bar once a navigation starts', () => {
    renderPage(<InertiaRouteIndicator />);
    expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();

    fireRouterEvent('start');

    expect(screen.getByRole('progressbar')).toBeInTheDocument();
  });

  it('hides the progress bar again once the navigation finishes', () => {
    renderPage(<InertiaRouteIndicator />);

    fireRouterEvent('start');
    expect(screen.getByRole('progressbar')).toBeInTheDocument();

    fireRouterEvent('finish');
    expect(screen.queryByRole('progressbar')).not.toBeInTheDocument();
  });

  it('unsubscribes from both events on unmount', () => {
    const unsubStart = vi.fn();
    const unsubFinish = vi.fn();
    vi.mocked(router.on)
      .mockReturnValueOnce(unsubStart)
      .mockReturnValueOnce(unsubFinish);

    const { unmount } = renderPage(<InertiaRouteIndicator />);
    expect(unsubStart).not.toHaveBeenCalled();
    expect(unsubFinish).not.toHaveBeenCalled();

    unmount();

    expect(unsubStart).toHaveBeenCalledTimes(1);
    expect(unsubFinish).toHaveBeenCalledTimes(1);
  });
});
