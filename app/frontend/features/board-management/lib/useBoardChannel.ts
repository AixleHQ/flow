import { createConsumer, type Consumer, type Subscription } from '@rails/actioncable';
import { useEffect, useRef, useState } from 'react';

import type { BoardTask } from 'entities/board-task';
import { QueryTag } from 'shared/api';
import { keysToCamelCase } from 'shared/lib/caseConverter';

import { boardApi } from '../api/boardApi';

import { useAppDispatch } from './useAppDispatch';

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
  const consumerRef = useRef<Consumer | null>(null);
  const subscriptionRef = useRef<Subscription | null>(null);
  const [connected, setConnected] = useState(false);
  const dispatch = useAppDispatch();

  useEffect(() => {
    if (!boardId) {
      setConnected(false);
      return;
    }

    if (!consumerRef.current) {
      consumerRef.current = createConsumer();
    }

    const subscription = consumerRef.current.subscriptions.create(
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
          const data = keysToCamelCase(message.data) as Record<string, unknown>;

          switch (message.type) {
            case 'task_created':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  draft.tasks.push(data as unknown as BoardTask);
                }),
              );
              break;

            case 'task_updated':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const idx = draft.tasks.findIndex((t) => t.id === (data as unknown as BoardTask).id);
                  if (idx >= 0) draft.tasks[idx] = data as unknown as BoardTask;
                }),
              );
              break;

            case 'task_deleted':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  draft.tasks = draft.tasks.filter((t) => t.id !== (data.taskId as number));
                }),
              );
              break;

            case 'task_moved':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const task = draft.tasks.find((t) => t.id === (data.taskId as number));
                  if (task) {
                    task.boardColumnId = data.toColumnId as number;
                    task.position = data.position as number;
                  }
                }),
              );
              break;

            case 'comment_added':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const task = draft.tasks.find((t) => t.id === (data.taskId as number));
                  if (task) task.commentsCount += 1;
                }),
              );
              dispatch(boardApi.util.invalidateTags([QueryTag.Comment]));
              break;

            case 'workflow_started':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const task = draft.tasks.find((t) => t.id === (data.taskId as number));
                  if (task) {
                    task.activeWorkflowRun = { id: data.runId as number, status: 'running' };
                  }
                }),
              );
              dispatch(boardApi.util.invalidateTags([QueryTag.WorkflowRun]));
              break;

            case 'workflow_completed':
            case 'workflow_failed':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const task = draft.tasks.find((t) => t.id === (data.taskId as number));
                  if (task) task.activeWorkflowRun = null;
                }),
              );
              dispatch(boardApi.util.invalidateTags([QueryTag.WorkflowRun]));
              break;

            case 'human_help_requested':
              dispatch(
                boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
                  const task = draft.tasks.find((t) => t.id === (data.taskId as number));
                  if (task && task.activeWorkflowRun) {
                    task.activeWorkflowRun.status = 'paused';
                  }
                }),
              );
              break;

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
