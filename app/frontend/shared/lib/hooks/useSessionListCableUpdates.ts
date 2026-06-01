import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef } from 'react';

import { getConsumer } from '../actionCableConsumer';

interface Options {
  projectId?: number;
  onUpdate: (session: Record<string, unknown>) => void;
}

/**
 * Subscribes to SessionListChannel and calls onUpdate whenever the server
 * broadcasts a session_update event. Only fires for sessions already visible
 * in the list — filtering by presence in the caller's Map is the caller's
 * responsibility.
 *
 * Uses the same StrictMode-safe deferred-subscribe pattern as
 * useInertiaCableStream: the 50ms setTimeout lets React's synchronous
 * mount→unmount→mount cancel the first attempt before it reaches ActionCable.
 */
export function useSessionListCableUpdates({ projectId, onUpdate }: Options) {
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  useEffect(() => {
    let sub: Subscription | null = null;
    let cancelled = false;

    const timer = setTimeout(() => {
      if (cancelled) return;

      const consumer = getConsumer();
      const params = projectId != null ? { project_id: projectId } : {};

      sub = consumer.subscriptions.create(
        { channel: 'SessionListChannel', ...params },
        {
          connected() {
            console.log('[SessionListChannel] connected', { projectId });
          },
          disconnected() {
            console.log('[SessionListChannel] disconnected', { projectId });
          },
          rejected() {
            console.warn('[SessionListChannel] rejected', { projectId });
          },
          received(data: { type: string; session: Record<string, unknown> }) {
            if (data.type === 'session_update') {
              onUpdateRef.current(data.session);
            }
          },
        } as unknown as Subscription,
      );
    }, 50);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      sub?.unsubscribe();
    };
  }, [projectId]);
}
