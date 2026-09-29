import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef } from 'react';

import { getConsumer } from '../actionCableConsumer';

export interface RowChanges {
  sessionIds: number[];
  runIds: number[];
}

interface Options {
  debounceMs?: number;
  /**
   * Every row the list shows. Broadcasts sent while the socket was down are gone,
   * so after a reconnect all of these are fetched back, in batches the rows
   * endpoints accept.
   */
  resyncIds?: () => RowChanges;
}

// The rows endpoints answer at most this many ids per request (ROWS_LIMIT).
const RESYNC_BATCH = 100;

const KINDS: Record<string, keyof RowChanges> = { session_update: 'sessionIds', run_update: 'runIds' };

/**
 * Tells a live list which of its rows changed. The server sends ids only — one
 * message reaches every subscriber and cannot be redacted per viewer — so the
 * caller fetches the rows back through its own authorized endpoint. The signed
 * stream name comes from the page's props: only a page that authorized its
 * viewer hands one out.
 *
 * Ids arriving within `debounceMs` of each other are delivered together, so a
 * burst of updates costs one fetch.
 */
export function useCableRowUpdates(
  signedStreamName: string | undefined,
  onChanges: (changes: RowChanges) => void,
  { debounceMs = 250, resyncIds }: Options = {},
) {
  const onChangesRef = useRef(onChanges);
  onChangesRef.current = onChanges;
  const resyncIdsRef = useRef(resyncIds);
  resyncIdsRef.current = resyncIds;

  useEffect(() => {
    if (!signedStreamName) return;

    let sub: Subscription | null = null;
    let cancelled = false;
    let connectedBefore = false;
    let flushTimer: ReturnType<typeof setTimeout> | null = null;
    const pending: Record<keyof RowChanges, Set<number>> = { sessionIds: new Set(), runIds: new Set() };

    const flush = () => {
      flushTimer = null;
      const changes = { sessionIds: [...pending.sessionIds], runIds: [...pending.runIds] };
      pending.sessionIds.clear();
      pending.runIds.clear();
      if (changes.sessionIds.length > 0 || changes.runIds.length > 0) onChangesRef.current(changes);
    };

    const resync = () => {
      const all = resyncIdsRef.current?.();
      if (!all) return;
      for (let i = 0; i < Math.max(all.sessionIds.length, all.runIds.length); i += RESYNC_BATCH) {
        onChangesRef.current({
          sessionIds: all.sessionIds.slice(i, i + RESYNC_BATCH),
          runIds: all.runIds.slice(i, i + RESYNC_BATCH),
        });
      }
    };

    // Deferred like useInertiaCableStream: StrictMode's mount→unmount→mount
    // cancels the first attempt before it reaches ActionCable.
    const subscribeTimer = setTimeout(() => {
      if (cancelled) return;

      sub = getConsumer().subscriptions.create(
        { channel: 'InertiaCable::StreamChannel', signed_stream_name: signedStreamName },
        {
          connected() {
            if (connectedBefore) resync();
            connectedBefore = true;
          },
          received(data: { type?: string; id?: number }) {
            const kind = data.type ? KINDS[data.type] : undefined;
            if (!kind || typeof data.id !== 'number') return;

            pending[kind].add(data.id);
            if (flushTimer) clearTimeout(flushTimer);
            flushTimer = setTimeout(flush, debounceMs);
          },
          rejected() {
            console.warn('[useCableRowUpdates] rejected');
          },
        },
      );
    }, 50);

    return () => {
      cancelled = true;
      clearTimeout(subscribeTimer);
      if (flushTimer) clearTimeout(flushTimer);
      sub?.unsubscribe();
    };
  }, [signedStreamName, debounceMs]);
}
