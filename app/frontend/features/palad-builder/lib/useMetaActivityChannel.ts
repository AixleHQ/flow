import { type Subscription } from '@rails/actioncable';
import { useCallback, useEffect, useRef, useState } from 'react';

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
  type: 'meta_activity' | 'workflow_run.updated' | 'step_run.updated' | 'sub_step_run.updated';
  data: MetaActivity | Record<string, unknown>;
}

interface UseMetaActivityChannelOptions {
  runId: number | null;
  onRunUpdate?: () => void;
}

export function useMetaActivityChannel({ runId, onRunUpdate }: UseMetaActivityChannelOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const onRunUpdateRef = useRef(onRunUpdate);
  const [connected, setConnected] = useState(false);
  const [activities, setActivities] = useState<MetaActivity[]>([]);

  useEffect(() => {
    onRunUpdateRef.current = onRunUpdate;
  }, [onRunUpdate]);

  useEffect(() => {
    if (!runId) {
      setConnected(false);
      return;
    }

    setActivities([]);

    const consumer = getConsumer();
    const subscription = consumer.subscriptions.create(
      { channel: 'WorkflowRunChannel', run_id: runId },
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
          if (
            message.type === 'workflow_run.updated' ||
            message.type === 'step_run.updated' ||
            message.type === 'sub_step_run.updated'
          ) {
            onRunUpdateRef.current?.();
          }
        },
      },
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [runId]);

  const clearActivities = useCallback(() => setActivities([]), []);

  return { connected, activities, clearActivities };
}
