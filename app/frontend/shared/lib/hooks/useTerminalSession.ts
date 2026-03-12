import { type Subscription } from '@rails/actioncable';
import { useCallback, useEffect, useRef, useState } from 'react';

import type { ICreateTerminalSessionRequest, ITerminalSession } from 'entities/terminal-session';
import { useCreateTerminalSessionMutation, useFinishSessionMutation, useGetTerminalSessionQuery } from 'shared/api';
import { getConsumer } from 'shared/lib/actionCableConsumer';

interface SessionUpdateMessage {
  type: 'terminal_session.updated' | 'session_update' | 'auth_complete';
  data: { id?: number };
}

interface UseTerminalSessionOptions {
  sessionId: number | null;
  skip?: boolean;
  onAuthComplete?: () => void;
}

const MAX_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 2000;
const POLL_INTERVAL_MS = 3000;

export function useTerminalSession({ sessionId, skip = false, onAuthComplete }: UseTerminalSessionOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryCountRef = useRef(0);
  const onAuthCompleteRef = useRef(onAuthComplete);

  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [channelError, setChannelError] = useState<string | null>(null);
  const [authComplete, setAuthComplete] = useState(false);

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
            if (message.type === 'terminal_session.updated' || message.type === 'session_update') {
              refetch();
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
  }, [sessionId, skip, refetch]);

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
