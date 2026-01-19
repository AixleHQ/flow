import { useEffect, useRef, useCallback, useState } from 'react';
import { createConsumer, Subscription } from '@rails/actioncable';

interface TerminalMessage {
  type: 'output' | 'error' | 'disconnect';
  data?: string;
  message?: string;
  reason?: string;
}

interface UseTerminalWebSocketOptions {
  sessionId: string;
  stepName: string;
  onOutput: (data: string) => void;
  onError?: (message: string) => void;
  onDisconnect?: (reason: string) => void;
}

export function useTerminalWebSocket({
  sessionId,
  stepName,
  onOutput,
  onError,
  onDisconnect,
}: UseTerminalWebSocketOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const [connected, setConnected] = useState(false);
  const [connecting, setConnecting] = useState(false);

  useEffect(() => {
    if (!sessionId || !stepName) return;

    setConnecting(true);

    const consumer = createConsumer();

    const subscription = consumer.subscriptions.create(
      {
        channel: 'TerminalChannel',
        session_id: sessionId,
        step_name: stepName,
      },
      {
        connected() {
          setConnected(true);
          setConnecting(false);
        },
        disconnected() {
          setConnected(false);
          setConnecting(false);
          onDisconnect?.('WebSocket disconnected');
        },
        rejected() {
          setConnected(false);
          setConnecting(false);
          onError?.('Connection rejected - container may not be running');
        },
        received(message: TerminalMessage) {
          switch (message.type) {
            case 'output':
              if (message.data) {
                onOutput(message.data);
              }
              break;
            case 'error':
              onError?.(message.message || 'Unknown error');
              break;
            case 'disconnect':
              setConnected(false);
              onDisconnect?.(message.reason || 'Container disconnected');
              break;
          }
        },
      }
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [sessionId, stepName, onOutput, onError, onDisconnect]);

  const sendInput = useCallback((data: string) => {
    if (!subscriptionRef.current || !connected) return;

    subscriptionRef.current.perform('receive', { type: 'input', data });
  }, [connected]);

  const sendResize = useCallback((cols: number, rows: number) => {
    if (!subscriptionRef.current || !connected) return;

    subscriptionRef.current.perform('receive', { type: 'resize', cols, rows });
  }, [connected]);

  return {
    connected,
    connecting,
    sendInput,
    sendResize,
  };
}
