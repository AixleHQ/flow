import { router } from '@inertiajs/react';
import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef } from 'react';

import { getConsumer } from '../actionCableConsumer';

interface Options {
  only?: string[];
  except?: string[];
  enabled?: boolean;
  debounceMs?: number;
}

/**
 * StrictMode-safe replacement for @inertia-cable/react's useInertiaCable.
 *
 * Defers subscribe via setTimeout(50) so React StrictMode's synchronous
 * mount→unmount→mount cancels the first attempt before it reaches
 * ActionCable, producing a single clean subscription on the second mount.
 *
 * Coalesces rapid broadcasts with a configurable debounce (default 150ms)
 * to avoid visual flickering from multiple near-simultaneous refreshes.
 */
export function useInertiaCableStream(signedStreamName: string | undefined, options: Options = {}) {
  const { only, except, enabled = true, debounceMs = 150 } = options;

  const subRef = useRef<Subscription | null>(null);
  const optionsRef = useRef({ only, except });
  optionsRef.current = { only, except };
  const reloadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!signedStreamName || !enabled) return;

    let cancelled = false;
    let connectedBefore = false;

    const scheduleReload = () => {
      if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
      reloadTimerRef.current = setTimeout(() => {
        reloadTimerRef.current = null;
        const opts = optionsRef.current;
        router.reload({
          ...(opts.only ? { only: opts.only } : {}),
          ...(opts.except ? { except: opts.except } : {}),
        });
      }, debounceMs);
    };

    const timer = setTimeout(() => {
      if (cancelled) return;

      const consumer = getConsumer();
      subRef.current = consumer.subscriptions.create(
        { channel: 'InertiaCable::StreamChannel', signed_stream_name: signedStreamName },
        {
          // A refresh broadcast while the socket was down never arrives, so a
          // reconnect reloads as if one had.
          connected() {
            if (connectedBefore) scheduleReload();
            connectedBefore = true;
          },
          rejected() {
            console.warn('[InertiaCableStream] rejected', { signedStreamName });
          },
          received(data: Record<string, unknown>) {
            if (data.type === 'refresh') scheduleReload();
          },
        } as unknown as Subscription,
      );
    }, 50);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      if (reloadTimerRef.current) {
        clearTimeout(reloadTimerRef.current);
        reloadTimerRef.current = null;
      }
      if (subRef.current) {
        subRef.current.unsubscribe();
        subRef.current = null;
      }
    };
  }, [signedStreamName, enabled, debounceMs]);
}
