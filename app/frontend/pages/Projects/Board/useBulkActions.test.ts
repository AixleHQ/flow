import { notifications } from '@mantine/notifications';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { act, renderHook } from 'test/renderPage';

import { useBulkActions } from './useBulkActions';

const PROJECT_ID = 7;

const answer = (status: number) => new Response('{}', { status, headers: { 'Content-Type': 'application/json' } });

describe('useBulkActions', () => {
  afterEach(() => vi.restoreAllMocks());

  it('counts only the tasks the server actually updated', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url) =>
      answer(url === `/api/v1/projects/${PROJECT_ID}/tasks/2` ? 403 : 200),
    );
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useBulkActions({ projectId: PROJECT_ID, onSuccess: vi.fn() }));

    await act(async () => {
      await result.current.bulkSetPriority([1, 2, 3], 'high');
    });

    expect(show).toHaveBeenCalledWith(
      expect.objectContaining({ color: 'yellow', message: 'Updated priority for 2 of 3 tasks. 1 not saved.' }),
    );
  });

  it('reports a failure when every update was refused', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(answer(403));
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useBulkActions({ projectId: PROJECT_ID, onSuccess: vi.fn() }));

    await act(async () => {
      await result.current.bulkAssign([1, 2], { kind: 'user', id: 42 });
    });

    expect(show).toHaveBeenCalledWith(
      expect.objectContaining({ color: 'red', message: 'Failed to update assignee. Please try again.' }),
    );
  });

  it('assigns a team in place of a person, clearing the person', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(answer(200));
    vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useBulkActions({ projectId: PROJECT_ID, onSuccess: vi.fn() }));

    await act(async () => {
      await result.current.bulkAssign([1], { kind: 'team', id: 7 });
    });

    const [, init] = fetchSpy.mock.calls[0];
    expect(JSON.parse(String(init?.body))).toEqual({ board_task: { assignee_id: null, assignee_team_id: 7 } });
  });

  it('confirms the update when every task was saved', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(answer(200));
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useBulkActions({ projectId: PROJECT_ID, onSuccess: vi.fn() }));

    await act(async () => {
      await result.current.bulkSetPriority([1], 'low');
    });

    expect(show).toHaveBeenCalledWith(
      expect.objectContaining({ color: 'green', message: 'Updated priority for 1 task.' }),
    );
  });
});
