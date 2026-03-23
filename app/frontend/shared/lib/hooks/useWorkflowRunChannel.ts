import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useCallback, useState } from 'react';

import { getConsumer } from 'shared/lib/actionCableConsumer';

interface RunUpdateMessage {
  type: 'workflow_run.updated' | 'step_run.updated' | 'sub_step_run.updated';
  data: { id?: number; workflow_run_id?: number; step_run_id?: number };
}

interface UseWorkflowRunChannelOptions {
  runId: number | null;
  onUpdate?: () => void;
}

export function useWorkflowRunChannel({ runId, onUpdate }: UseWorkflowRunChannelOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const onUpdateRef = useRef(onUpdate);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    onUpdateRef.current = onUpdate;
  }, [onUpdate]);

  useEffect(() => {
    if (!runId) {
      setConnected(false);
      return;
    }

    const consumer = getConsumer();
    const subscription = consumer.subscriptions.create(
      { channel: 'WorkflowRunChannel', run_id: runId },
      {
        connected() {
          setConnected(true);
          onUpdateRef.current?.();
        },
        disconnected() {
          setConnected(false);
        },
        rejected() {
          setConnected(false);
        },
        received(message: RunUpdateMessage) {
          if (
            message.type === 'workflow_run.updated' ||
            message.type === 'step_run.updated' ||
            message.type === 'sub_step_run.updated'
          ) {
            onUpdateRef.current?.();
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

  const refresh = useCallback(() => {
    if (!subscriptionRef.current || !connected) return;
    subscriptionRef.current.perform('refresh');
  }, [connected]);

  return { connected, refresh };
}
