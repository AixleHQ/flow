import { type Subscription } from '@rails/actioncable';
import { useCallback, useEffect, useRef, useState } from 'react';
import { useDispatch } from 'react-redux';

import type { ICreateTerminalSessionRequest, ITerminalSession } from 'entities/terminal-session';
import type { AppDispatch } from 'shared/api';
import {
  terminalSessionApi,
  useCreateTerminalSessionMutation,
  useFinishSessionMutation,
  useGetTerminalSessionQuery,
} from 'shared/api';
import { getConsumer } from 'shared/lib/actionCableConsumer';
import { keysToCamelCase } from 'shared/lib/caseConverter';

interface SessionUpdateMessage {
  type: 'session_update' | 'auth_complete';
  data: Record<string, unknown>;
}

interface UseTerminalSessionOptions {
  sessionId: number | null;
  skip?: boolean;
  onUpdate?: (session: ITerminalSession) => void;
  onAuthComplete?: () => void;
}

const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 2000;
const POLL_INTERVAL_MS = 3000;

export function useTerminalSession({ sessionId, skip = false, onUpdate, onAuthComplete }: UseTerminalSessionOptions) {
  const dispatch = useDispatch<AppDispatch>();
  const subscriptionRef = useRef<Subscription | null>(null);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryCountRef = useRef(0);
  const onUpdateRef = useRef(onUpdate);
  const onAuthCompleteRef = useRef(onAuthComplete);

  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [channelError, setChannelError] = useState<string | null>(null);
  const [authComplete, setAuthComplete] = useState(false);

  useEffect(() => {
    onUpdateRef.current = onUpdate;
  }, [onUpdate]);
  useEffect(() => {
    onAuthCompleteRef.current = onAuthComplete;
  }, [onAuthComplete]);

  const shouldFetch = !!sessionId && !skip;

  const {
    data: queryData,
    isLoading,
    isError: isQueryError,
    isFetching,
    refetch,
  } = useGetTerminalSessionQuery(sessionId!, { skip: !shouldFetch });

  const session: ITerminalSession | null = shouldFetch ? (queryData?.data ?? null) : null;

  const patchSessionCache = useCallback(
    (updated: ITerminalSession) => {
      if (!sessionId) return;
      dispatch(
        terminalSessionApi.util.updateQueryData('getTerminalSession', sessionId, (draft) => {
          Object.assign(draft.data, updated);
        }),
      );
    },
    [dispatch, sessionId],
  );

  useEffect(() => {
    if (!sessionId || skip) {
      setConnected(false);
      setConnecting(false);
      return;
    }

    let cancelled = false;
    retryCountRef.current = 0;

    function subscribe() {
      if (cancelled) return;

      setConnecting(true);
      setChannelError(null);

      const consumer = getConsumer();
      const subscription = consumer.subscriptions.create(
        { channel: 'TerminalSessionChannel', session_id: sessionId },
        {
          connected() {
            if (cancelled) return;
            retryCountRef.current = 0;
            setConnected(true);
            setConnecting(false);
            setChannelError(null);
          },
          disconnected() {
            if (cancelled) return;
            setConnected(false);
            setConnecting(false);
          },
          rejected() {
            if (cancelled) return;
            setConnected(false);
            setConnecting(false);

            if (retryCountRef.current < MAX_RETRIES) {
              const delay = RETRY_BASE_DELAY_MS * 2 ** retryCountRef.current;
              retryCountRef.current += 1;
              retryTimerRef.current = setTimeout(() => {
                subscriptionRef.current?.unsubscribe();
                subscribe();
              }, delay);
            } else {
              setChannelError('Connection rejected — session may not exist or you do not have access');
            }
          },
          received(message: SessionUpdateMessage) {
            if (message.type === 'session_update' && message.data) {
              const updated = keysToCamelCase(message.data) as unknown as ITerminalSession;
              patchSessionCache(updated);
              onUpdateRef.current?.(updated);
            } else if (message.type === 'auth_complete') {
              setAuthComplete(true);
              onAuthCompleteRef.current?.();
            }
          },
        },
      );

      subscriptionRef.current = subscription;
    }

    subscribe();

    return () => {
      cancelled = true;
      if (retryTimerRef.current) clearTimeout(retryTimerRef.current);
      subscriptionRef.current?.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [sessionId, skip, patchSessionCache]);

  const refresh = useCallback(() => {
    if (connected) {
      subscriptionRef.current?.perform('refresh');
    }
    if (shouldFetch) {
      refetch();
    }
  }, [connected, shouldFetch, refetch]);

  const isTerminal = session?.state === 'finished' || session?.state === 'failed';
  const isReady = session?.state === 'ready';

  useEffect(() => {
    if (!shouldFetch || isReady || isTerminal) return;

    const timer = setInterval(() => {
      if (shouldFetch) refetch();
    }, POLL_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [shouldFetch, isReady, isTerminal, refetch]);

  const [createSessionMutation, { isLoading: isCreating }] = useCreateTerminalSessionMutation();
  const [finishSessionMutation, { isLoading: isFinishing }] = useFinishSessionMutation();

  const createSession = useCallback(
    async (request: ICreateTerminalSessionRequest) => {
      return createSessionMutation(request).unwrap();
    },
    [createSessionMutation],
  );

  const finishSession = useCallback(
    async (id: number) => {
      return finishSessionMutation({ sessionId: id }).unwrap();
    },
    [finishSessionMutation],
  );

  return {
    session,
    isLoading,
    isFetching,
    isError: isQueryError,

    connected,
    connecting,
    channelError,
    authComplete,
    refresh,

    createSession,
    isCreating,
    finishSession,
    isFinishing,
  };
}
