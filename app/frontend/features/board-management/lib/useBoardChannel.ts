import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useState } from 'react';

import { QueryTag } from 'shared/api';
import { getConsumer } from 'shared/lib/actionCableConsumer';

import { boardApi, scheduleBoardTaskRealtimeSync } from '../api/boardApi';

import { useAppDispatch } from './useAppDispatch';

interface BoardEvent {
  type: string;
  data: { id?: number; board_id?: number };
  actor_id?: number;
}

interface UseBoardChannelOptions {
  boardId: number | null;
  projectId: number;
}

export function useBoardChannel({ boardId, projectId }: UseBoardChannelOptions) {
  const subscriptionRef = useRef<Subscription | null>(null);
  const [connected, setConnected] = useState(false);
  const dispatch = useAppDispatch();

  useEffect(() => {
    if (!boardId) {
      setConnected(false);
      return;
    }

    const consumer = getConsumer();
    const subscription = consumer.subscriptions.create(
      { channel: 'BoardChannel', board_id: boardId },
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
        received(message: BoardEvent) {
          switch (message.type) {
            case 'board_task.created':
            case 'board_task.updated':
              scheduleBoardTaskRealtimeSync(dispatch);
              break;

            case 'board_task.destroyed':
              if (message.data.id) {
                dispatch(
                  boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                    draft.tasks = draft.tasks.filter((t) => t.id !== message.data.id);
                  }),
                );
              }
              break;

            case 'board_activity.created':
              dispatch(boardApi.util.invalidateTags([QueryTag.Activity]));
              break;
          }
        },
      },
    );

    subscriptionRef.current = subscription;

    return () => {
      subscription.unsubscribe();
      subscriptionRef.current = null;
    };
  }, [boardId, projectId, dispatch]);

  return { connected };
}
