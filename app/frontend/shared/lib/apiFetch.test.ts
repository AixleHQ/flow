import { notifications } from '@mantine/notifications';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { ApiError, apiMutate, apiRequest } from './apiFetch';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

describe('apiRequest', () => {
  afterEach(() => vi.restoreAllMocks());

  it('resolves with the parsed body of a successful answer', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(json({ id: 12, name: 'Backlog' }, 201));

    await expect(apiRequest('/api/v1/projects/7/columns', { method: 'POST' })).resolves.toEqual({
      id: 12,
      name: 'Backlog',
    });
  });

  it('resolves with nothing for a 204', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 204 }));

    await expect(apiRequest('/api/v1/projects/7/columns/12', { method: 'DELETE' })).resolves.toBeUndefined();
  });

  it("rejects a refusal with the server's own reason", async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(json({ error: 'You cannot edit this board' }, 403));

    const error = await apiRequest('/api/v1/projects/7/tasks/3', { method: 'PATCH' }).catch((e: unknown) => e);

    expect(error).toBeInstanceOf(ApiError);
    expect(error).toMatchObject({ status: 403, message: 'You cannot edit this board' });
  });

  it('joins a list of validation errors into one reason', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      json({ errors: ['Name is too long', 'would create a cycle: A → B → A'] }, 422),
    );

    await expect(apiRequest('/api/v1/projects/7/workflows/3/steps/1')).rejects.toThrow(
      'Name is too long, would create a cycle: A → B → A',
    );
  });

  it('names the status when the answer carries no reason', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('<html>Bad gateway</html>', { status: 502 }));

    await expect(apiRequest('/api/v1/projects/7/tasks')).rejects.toThrow('Request failed (502)');
  });
});

describe('apiMutate', () => {
  afterEach(() => vi.restoreAllMocks());

  it('resolves true and stays quiet when the change is saved', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(json({}));
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');

    await expect(apiMutate('/api/v1/projects/7/tasks/3', { method: 'PATCH' })).resolves.toBe(true);
    expect(show).not.toHaveBeenCalled();
  });

  it("resolves false and shows the server's reason when the change is refused", async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(json({ error: 'Task is archived' }, 422));
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');

    await expect(apiMutate('/api/v1/projects/7/tasks/3', { method: 'PATCH' })).resolves.toBe(false);
    expect(show).toHaveBeenCalledWith(expect.objectContaining({ color: 'red', message: 'Task is archived' }));
  });

  it('resolves false with the fallback message when the request never arrives', async () => {
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('Failed to fetch'));
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');

    await expect(
      apiMutate('/api/v1/projects/7/tasks/3', { method: 'DELETE' }, 'The task was not deleted'),
    ).resolves.toBe(false);
    expect(show).toHaveBeenCalledWith(expect.objectContaining({ message: 'The task was not deleted' }));
  });
});

describe('apiFetch step-up', () => {
  const originalLocation = window.location;
  const assign = vi.fn();

  beforeEach(() => {
    assign.mockReset();
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: { assign } });
  });

  afterEach(() => {
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: originalLocation });
    vi.restoreAllMocks();
  });

  const settles = async (promise: Promise<unknown>) => {
    let done = false;
    void promise.then(
      () => (done = true),
      () => (done = true),
    );
    await new Promise((resolve) => setTimeout(resolve, 0));
    return done;
  };

  it("goes to the company's step-up page instead of reporting the refusal", async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      json({ error: 'step_up_required', stepUpUrl: '/step_up?company_id=4' }, 403),
    );
    const show = vi.spyOn(notifications, 'show').mockImplementation(() => '');

    const saved = apiMutate('/api/v1/projects/7/tasks/3', { method: 'PATCH' });

    expect(await settles(saved)).toBe(false);
    expect(assign).toHaveBeenCalledWith('/step_up?company_id=4');
    expect(show).not.toHaveBeenCalled();
  });

  it('reports any other refusal as before', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(json({ error: 'Not authorized' }, 403));

    await expect(apiRequest('/api/v1/projects/7/board/tasks')).rejects.toThrow('Not authorized');
    expect(assign).not.toHaveBeenCalled();
  });

  it('does not follow a step-up address off this site', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      json({ error: 'step_up_required', stepUpUrl: '//elsewhere.example/step_up' }, 403),
    );

    await expect(apiRequest('/api/v1/projects/7/board/tasks')).rejects.toBeInstanceOf(ApiError);
    expect(assign).not.toHaveBeenCalled();
  });
});
