import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useState } from 'react';

import { getConsumer } from 'shared/lib/actionCableConsumer';

export interface MetaActivity {
  action: string;
  entityType: string;
  entityName: string;
  entityId: number;
  details: Record<string, unknown>;
  timestamp: string;
}

interface MetaActivityMessage {
  type: 'meta_activity' | 'terminal_session.updated' | 'session_update';
  data: MetaActivity | Record<string, unknown>;
}

interface UseMetaActivityChannelOptions {
  sessionId: number | null;
}

export function useMetaActivityChannel({ sessionId }: UseMetaActivityChannelOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const [connected, setConnected] = useState(false);
  const [activities, setActivities] = useState<MetaActivity[]>([]);

  useEffect(() => {
    if (!sessionId) {
      setConnected(false);
      return;
    }

    setActivities([]);

    const consumer = getConsumer();
    const subscription = consumer.subscriptions.create(
      { channel: 'TerminalSessionChannel', session_id: sessionId },
      {
        connected() {
          setConnected(true);
        },
        disconnected() {
          setConnected(false);
        },
        rejected() {
          setConnected(false);
        },
        received(message: MetaActivityMessage) {
          if (message.type === 'meta_activity') {
            setActivities((prev) => [...prev, message.data as MetaActivity]);
          }
        },
      },
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [sessionId]);

  return { connected, activities };
}
