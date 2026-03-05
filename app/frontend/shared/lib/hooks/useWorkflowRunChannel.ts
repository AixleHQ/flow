import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useCallback, useState } from 'react';

import { getConsumer } from 'shared/lib/actionCableConsumer';
import { keysToCamelCase } from 'shared/lib/caseConverter';

interface RunUpdateMessage {
  type: 'run_update' | 'step_run_update' | 'sub_step_run_update';
  data: Record<string, unknown>;
}

interface UseWorkflowRunChannelOptions<T = unknown> {
  runId: number | null;
  onUpdate?: (run: T) => void;
}

export function useWorkflowRunChannel<T = unknown>({ runId, onUpdate }: UseWorkflowRunChannelOptions<T>) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const onUpdateRef = useRef(onUpdate);
  const [workflowRun, setWorkflowRun] = useState<T | null>(null);
  const [connected, setConnected] = useState(false);

  useEffect(() => {
    onUpdateRef.current = onUpdate;
  }, [onUpdate]);

  useEffect(() => {
    if (!runId) {
      setWorkflowRun(null);
      setConnected(false);
      return;
    }

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
        received(message: RunUpdateMessage) {
          if (message.type === 'run_update' && message.data) {
            const run = keysToCamelCase(message.data) as unknown as T;
            setWorkflowRun(run);
            onUpdateRef.current?.(run);
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

  return { workflowRun, connected, refresh };
}
