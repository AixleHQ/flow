import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderHook } from 'test/renderPage';

import { useInertiaCableStream } from './useInertiaCableStream';

// Capture the channel params + handlers passed to subscriptions.create so we can
// drive the `received` callback and assert subscribe/unsubscribe. The shared
// @rails/actioncable mock ignores the handlers, so we control getConsumer here.
type CableHandlers = {
  connected: () => void;
  disconnected: () => void;
  rejected: () => void;
  received: (data: Record<string, unknown>) => void;
};

const unsubscribe = vi.fn();
const create = vi.fn();
let lastHandlers: CableHandlers | null = null;

vi.mock('../actionCableConsumer', () => ({
  getConsumer: () => ({
    subscriptions: {
      create: (params: Record<string, unknown>, handlers: CableHandlers) => {
        lastHandlers = handlers;
        return create(params, handlers);
      },
    },
  }),
}));

describe('useInertiaCableStream', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    lastHandlers = null;
    create.mockReturnValue({ unsubscribe });
  });

  afterEach(() => {
    vi.runOnlyPendingTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('does not subscribe when no signed stream name is given', () => {
    renderHook(() => useInertiaCableStream(undefined));
    act(() => vi.advanceTimersByTime(100));
    expect(create).not.toHaveBeenCalled();
  });

  it('does not subscribe when disabled', () => {
    renderHook(() => useInertiaCableStream('signed-abc', { enabled: false }));
    act(() => vi.advanceTimersByTime(100));
    expect(create).not.toHaveBeenCalled();
  });

  it('subscribes to InertiaCable::StreamChannel after the deferred timer', () => {
    renderHook(() => useInertiaCableStream('signed-stream-xyz'));

    // The 50ms defer means nothing happens synchronously.
    expect(create).not.toHaveBeenCalled();

    act(() => vi.advanceTimersByTime(50));

    expect(create).toHaveBeenCalledTimes(1);
    expect(create).toHaveBeenCalledWith(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: 'signed-stream-xyz' },
      expect.any(Object),
    );
  });

  it('reloads (debounced) with only/except on a refresh broadcast', () => {
    renderHook(() =>
      useInertiaCableStream('signed-stream-xyz', { only: ['board'], except: ['flash'] }),
    );
    act(() => vi.advanceTimersByTime(50));

    act(() => lastHandlers?.received({ type: 'refresh' }));

    // Debounced: still nothing right after the broadcast.
    expect(router.reload).not.toHaveBeenCalled();

    act(() => vi.advanceTimersByTime(150));

    expect(router.reload).toHaveBeenCalledTimes(1);
    expect(router.reload).toHaveBeenCalledWith({ only: ['board'], except: ['flash'] });
  });

  it('coalesces rapid refresh broadcasts into a single reload', () => {
    renderHook(() => useInertiaCableStream('signed-stream-xyz'));
    act(() => vi.advanceTimersByTime(50));

    act(() => {
      lastHandlers?.received({ type: 'refresh' });
      vi.advanceTimersByTime(50);
      lastHandlers?.received({ type: 'refresh' });
      vi.advanceTimersByTime(50);
      lastHandlers?.received({ type: 'refresh' });
    });

    act(() => vi.advanceTimersByTime(150));

    expect(router.reload).toHaveBeenCalledTimes(1);
  });

  it('ignores non-refresh broadcasts', () => {
    renderHook(() => useInertiaCableStream('signed-stream-xyz'));
    act(() => vi.advanceTimersByTime(50));

    act(() => lastHandlers?.received({ type: 'something_else' }));
    act(() => vi.advanceTimersByTime(500));

    expect(router.reload).not.toHaveBeenCalled();
  });

  it('cancels the deferred subscribe when unmounted before it fires (StrictMode-safe)', () => {
    const { unmount } = renderHook(() => useInertiaCableStream('signed-stream-xyz'));

    // Unmount within the 50ms window: the pending subscribe must be cancelled.
    unmount();
    act(() => vi.advanceTimersByTime(100));

    expect(create).not.toHaveBeenCalled();
  });

  it('unsubscribes on unmount after it has subscribed', () => {
    const { unmount } = renderHook(() => useInertiaCableStream('signed-stream-xyz'));
    act(() => vi.advanceTimersByTime(50));
    expect(create).toHaveBeenCalledTimes(1);

    unmount();

    expect(unsubscribe).toHaveBeenCalledTimes(1);
  });
});
