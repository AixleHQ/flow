import { useEffect, useRef, useCallback, useState } from 'react';
import { createConsumer, Consumer, Subscription } from '@rails/actioncable';

import type { ITerminalSession } from 'entities/terminal-session/model/types';
import { keysToCamelCase } from 'shared/lib/caseConverter';

interface SessionUpdateMessage {
  type: 'session_update' | 'auth_complete';
  data: Record<string, unknown>;
}

interface UseTerminalSessionChannelOptions {
  sessionId: number | null;
  onUpdate?: (session: ITerminalSession) => void;
  onAuthComplete?: () => void;
}

/**
 * Hook for subscribing to real-time terminal session updates via ActionCable
 *
 * Usage:
 * const { session, connected, refresh } = useTerminalSessionChannel({
 *   sessionId: 123,
 *   onUpdate: (session) => console.log('Session updated:', session)
 * });
 */
export function useTerminalSessionChannel({
  sessionId,
  onUpdate,
  onAuthComplete,
}: UseTerminalSessionChannelOptions) {
  const consumerRef = useRef<Consumer | null>(null);
  const subscriptionRef = useRef<Subscription | null>(null);
  const onUpdateRef = useRef(onUpdate);
  const onAuthCompleteRef = useRef(onAuthComplete);
  const [session, setSession] = useState<ITerminalSession | null>(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [authComplete, setAuthComplete] = useState(false);

  // Keep callback refs fresh without triggering re-subscription
  useEffect(() => {
    onUpdateRef.current = onUpdate;
  }, [onUpdate]);

  useEffect(() => {
    onAuthCompleteRef.current = onAuthComplete;
  }, [onAuthComplete]);

  useEffect(() => {
    if (!sessionId) {
      setSession(null);
      setConnected(false);
      return;
    }

    setConnecting(true);
    setError(null);

    // Create consumer if not exists
    if (!consumerRef.current) {
      consumerRef.current = createConsumer();
    }

    const subscription = consumerRef.current.subscriptions.create(
      {
        channel: 'TerminalSessionChannel',
        session_id: sessionId,
      },
      {
        connected() {
          console.log('[ActionCable] Connected to TerminalSessionChannel', sessionId);
          setConnected(true);
          setConnecting(false);
          setError(null);
        },
        disconnected() {
          console.log('[ActionCable] Disconnected from TerminalSessionChannel', sessionId);
          setConnected(false);
          setConnecting(false);
        },
        rejected() {
          console.log('[ActionCable] Rejected from TerminalSessionChannel', sessionId);
          setConnected(false);
          setConnecting(false);
          setError('Connection rejected - session may not exist or you do not have access');
        },
        received(message: SessionUpdateMessage) {
          console.log('[ActionCable] Received message:', message);
          if (message.type === 'session_update' && message.data) {
            const session = keysToCamelCase(message.data) as unknown as ITerminalSession;
            setSession(session);
            onUpdateRef.current?.(session);
          } else if (message.type === 'auth_complete') {
            console.log('[ActionCable] Auth complete detected!');
            setAuthComplete(true);
            onAuthCompleteRef.current?.();
          }
        },
      }
    );

    subscriptionRef.current = subscription;

    return () => {
      console.log('[ActionCable] Unsubscribing from TerminalSessionChannel', sessionId);
      subscription.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [sessionId]);

  // Request fresh data from server
  const refresh = useCallback(() => {
    if (!subscriptionRef.current || !connected) return;
    subscriptionRef.current.perform('refresh');
  }, [connected]);

  return {
    session,
    connected,
    connecting,
    error,
    authComplete,
    refresh,
  };
}
