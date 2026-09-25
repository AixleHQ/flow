import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderHook } from 'test/renderPage';

import { useCableRowUpdates } from './useCableRowUpdates';

type CableHandlers = { connected: () => void; received: (data: Record<string, unknown>) => void };

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

describe('useCableRowUpdates', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    lastHandlers = null;
    create.mockReturnValue({ unsubscribe });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
  });

  it('does not subscribe without a signed stream', () => {
    renderHook(() => useCableRowUpdates(undefined, vi.fn()));
    act(() => vi.advanceTimersByTime(100));

    expect(create).not.toHaveBeenCalled();
  });

  it('delivers a burst of updates as one batch of ids', () => {
    const onChanges = vi.fn();
    renderHook(() => useCableRowUpdates('signed-stream', onChanges));
    act(() => vi.advanceTimersByTime(100));

    expect(create).toHaveBeenCalledWith(
      { channel: 'InertiaCable::StreamChannel', signed_stream_name: 'signed-stream' },
      expect.anything(),
    );

    act(() => {
      lastHandlers!.received({ type: 'session_update', id: 1 });
      lastHandlers!.received({ type: 'session_update', id: 1 });
      lastHandlers!.received({ type: 'run_update', id: 7 });
      lastHandlers!.received({ type: 'refresh' });
      lastHandlers!.received({ type: 'session_update', id: 'not-an-id' });
    });
    expect(onChanges).not.toHaveBeenCalled();

    act(() => vi.advanceTimersByTime(250));

    expect(onChanges).toHaveBeenCalledTimes(1);
    expect(onChanges).toHaveBeenCalledWith({ sessionIds: [1], runIds: [7] });
  });

  it('fetches back every row it shows after a reconnect, in batches the rows endpoints accept', () => {
    const onChanges = vi.fn();
    const shown = Array.from({ length: 150 }, (_, i) => i + 1);
    renderHook(() =>
      useCableRowUpdates('signed-stream', onChanges, { resyncIds: () => ({ sessionIds: shown, runIds: [7] }) }),
    );
    act(() => vi.advanceTimersByTime(50));

    act(() => lastHandlers!.connected());
    expect(onChanges).not.toHaveBeenCalled();

    act(() => lastHandlers!.connected());

    expect(onChanges).toHaveBeenCalledTimes(2);
    expect(onChanges).toHaveBeenNthCalledWith(1, { sessionIds: shown.slice(0, 100), runIds: [7] });
    expect(onChanges).toHaveBeenNthCalledWith(2, { sessionIds: shown.slice(100), runIds: [] });
  });

  it('unsubscribes and drops a pending batch on unmount', () => {
    const onChanges = vi.fn();
    const { unmount } = renderHook(() => useCableRowUpdates('signed-stream', onChanges));
    act(() => vi.advanceTimersByTime(100));
    act(() => lastHandlers!.received({ type: 'session_update', id: 1 }));

    unmount();
    act(() => vi.advanceTimersByTime(500));

    expect(unsubscribe).toHaveBeenCalled();
    expect(onChanges).not.toHaveBeenCalled();
  });
});
