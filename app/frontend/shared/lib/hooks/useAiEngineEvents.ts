import { createConsumer, Consumer, Subscription } from '@rails/actioncable';
import { useEffect, useCallback, useRef } from 'react';

export type IAiEngineEvent = {
  id: number;
  type: 'Asset' | 'SpecificationVersion' | 'Domain' | 'Feature' | 'UserStory' | 'UseCase';
  data: unknown;
  change: 'update' | 'create' | 'destroy';
};

export interface IUseAiEngineEventsOptions {
  workspaceId?: number | string;
  specificationId?: number | string;
  onEvent?: (event: IAiEngineEvent) => void;
  logEvents?: boolean;
}

export function useAiEngineEvents(options: IUseAiEngineEventsOptions = {}) {
  const { workspaceId, specificationId, onEvent, logEvents = false } = options;

  const consumerRef = useRef<Consumer | null>(null);
  const workspaceSubscriptionRef = useRef<Subscription | null>(null);
  const specificationSubscriptionRef = useRef<Subscription | null>(null);

  const log = (message: unknown) => logEvents && console.info(message);

  const handleEvent = useCallback(
    (event: IAiEngineEvent) => {
      log(event);
      onEvent?.(event);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [onEvent],
  );

  useEffect(() => {
    if (!consumerRef.current) consumerRef.current = createConsumer();

    // Subscribe to workspace channel
    if (workspaceId) {
      workspaceSubscriptionRef.current = consumerRef.current.subscriptions.create(
        { channel: 'WorkspaceChannel', workspace_id: workspaceId },
        { received: handleEvent },
      );
      log(`🔗 Connected to workspace ${workspaceId} events`);
    }

    // Subscribe to specification version channel
    if (specificationId) {
      specificationSubscriptionRef.current = consumerRef.current.subscriptions.create(
        { channel: 'SpecificationChannel', specification_id: specificationId },
        { received: handleEvent },
      );
      log(`🔗 Connected to specification ${specificationId} events`);
    }

    return () => {
      if (workspaceSubscriptionRef.current) {
        workspaceSubscriptionRef.current.unsubscribe();
        workspaceSubscriptionRef.current = null;
        log('🔌 Unsubscribed from workspace channel');
      }
      if (specificationSubscriptionRef.current) {
        specificationSubscriptionRef.current.unsubscribe();
        specificationSubscriptionRef.current = null;
        log('🔌 Unsubscribed from specification channel');
      }
      if (consumerRef.current) {
        consumerRef.current.disconnect();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspaceId, specificationId, handleEvent]);

  return {};
}
