import { type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useState } from 'react';

import type { BoardTask } from 'entities/board-task';
import { QueryTag } from 'shared/api';
import { getConsumer } from 'shared/lib/actionCableConsumer';
import { keysToCamelCase } from 'shared/lib/caseConverter';

import { boardApi } from '../api/boardApi';

import { useAppDispatch } from './useAppDispatch';

interface TaskChangedData {
  action: 'created' | 'updated' | 'destroyed';
  id?: number;
  task?: BoardTask;
}

interface BoardEvent {
  type: string;
  data: Record<string, unknown>;
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
          const data = keysToCamelCase(message.data) as unknown as TaskChangedData;

          switch (message.type) {
            case 'task_changed': {
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  if (data.action === 'created' && data.task) {
                    const exists = draft.tasks.some((t) => t.id === data.task!.id);
                    if (!exists) draft.tasks.push(data.task);
                  } else if (data.action === 'updated' && data.task) {
                    const idx = draft.tasks.findIndex((t) => t.id === data.task!.id);
                    if (idx >= 0) draft.tasks[idx] = data.task;
                  } else if (data.action === 'destroyed' && data.id) {
                    draft.tasks = draft.tasks.filter((t) => t.id !== data.id);
                  }
                }),
              );
              if (data.action !== 'destroyed') {
                dispatch(boardApi.util.invalidateTags([QueryTag.Comment]));
              }
              break;
            }

            case 'activity_created':
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
