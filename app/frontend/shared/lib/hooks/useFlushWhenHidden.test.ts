import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderHook } from 'test/renderPage';

import { useFlushWhenHidden } from './useFlushWhenHidden';

const setVisibility = (state: DocumentVisibilityState) =>
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state });

describe('useFlushWhenHidden', () => {
  afterEach(() => setVisibility('visible'));

  it('sends what is still waiting when the tab is hidden, and nothing while it is visible', () => {
    const save = { flush: vi.fn() };
    const other = { flush: vi.fn() };
    renderHook(() => useFlushWhenHidden(save, other));

    document.dispatchEvent(new Event('visibilitychange'));
    expect(save.flush).not.toHaveBeenCalled();

    setVisibility('hidden');
    document.dispatchEvent(new Event('visibilitychange'));
    expect(save.flush).toHaveBeenCalledTimes(1);
    expect(other.flush).toHaveBeenCalledTimes(1);
  });
});
