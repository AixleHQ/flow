import { notifications } from '@mantine/notifications';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { act, renderHook } from 'test/renderPage';

import { useSavingState } from './useSavingState';

const answer = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

describe('useSavingState', () => {
  afterEach(() => vi.restoreAllMocks());

  it('reports a save the server accepted as saved', async () => {
    const { result } = renderHook(() => useSavingState());

    let saved: boolean | undefined;
    await act(async () => {
      saved = await result.current.withSave(Promise.resolve(answer({}, 200)));
    });

    expect(saved).toBe(true);
    expect(result.current.failed).toBe(false);
    expect(result.current.saving).toBe(false);
  });

  // fetch resolves for a 422 as well; reading that as "saved" would show a refused edit as the
  // green "Saved" chip.
  it("reports a refused save as failed and tells the user the server's reason", async () => {
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useSavingState());

    let saved: boolean | undefined;
    await act(async () => {
      saved = await result.current.withSave(
        Promise.resolve(answer({ errors: ['would create a cycle: Draft spec → Implement → Draft spec'] }, 422)),
      );
    });

    expect(saved).toBe(false);
    expect(result.current.failed).toBe(true);
    expect(show).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'would create a cycle: Draft spec → Implement → Draft spec' }),
    );
  });

  it('clears the failure once a later save goes through', async () => {
    vi.spyOn(notifications, 'show').mockImplementation(() => '');
    const { result } = renderHook(() => useSavingState());

    await act(async () => {
      await result.current.withSave(Promise.reject(new TypeError('Failed to fetch')));
    });
    expect(result.current.failed).toBe(true);

    await act(async () => {
      await result.current.withSave(Promise.resolve(answer({}, 200)));
    });
    expect(result.current.failed).toBe(false);
  });
});
