import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef } from 'react';

import { getConsumer } from '../actionCableConsumer';

interface Options {
  projectId: number;
  onUpdate: (run: Record<string, unknown>) => void;
}

export function useWorkflowRunListCableUpdates({ projectId, onUpdate }: Options) {
  const onUpdateRef = useRef(onUpdate);
  onUpdateRef.current = onUpdate;

  useEffect(() => {
    let sub: Subscription | null = null;
    let cancelled = false;

    const timer = setTimeout(() => {
      if (cancelled) return;

      const consumer = getConsumer();
      sub = consumer.subscriptions.create({ channel: 'WorkflowRunListChannel', project_id: projectId }, {
        connected() {},
        disconnected() {},
        rejected() {
          console.warn('[WorkflowRunListChannel] rejected', { projectId });
        },
        received(data: { type: string; run: Record<string, unknown> }) {
          if (data.type === 'run_update') {
            onUpdateRef.current(data.run);
          }
        },
      } as unknown as Subscription);
    }, 50);

    return () => {
      cancelled = true;
      clearTimeout(timer);
      sub?.unsubscribe();
    };
  }, [projectId]);
}
