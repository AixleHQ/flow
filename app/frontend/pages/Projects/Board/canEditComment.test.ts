import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildTaskComment } from 'test/factories/taskComment';

import { canEditComment } from './canEditComment';

// Mirrors the server rule (TaskComment#editable_by? / CommentsPolicy#update?): a
// comment is editable only by its own author, only when human-authored, and only
// while younger than 3 hours. The server is the real guard (403 on an expired or
// unauthorized edit); this helper only decides whether to offer the affordance.
describe('canEditComment', () => {
  // Pin "now" so the age window is deterministic regardless of when the suite runs.
  const NOW = new Date('2026-06-01T12:00:00Z');

  afterEach(() => {
    vi.useRealTimers();
  });

  const freeze = () => {
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
  };

  const minutesAgo = (m: number) => new Date(NOW.getTime() - m * 60 * 1000).toISOString();

  it('allows editing your own, human, fresh comment', () => {
    freeze();
    const c = buildTaskComment({ authorId: 1, authorType: 'human', createdAt: minutesAgo(10) });
    expect(canEditComment(c, 1)).toBe(true);
  });

  it("forbids editing another user's comment", () => {
    freeze();
    const c = buildTaskComment({ authorId: 2, authorType: 'human', createdAt: minutesAgo(10) });
    expect(canEditComment(c, 1)).toBe(false);
  });

  it('forbids editing an agent-authored comment', () => {
    freeze();
    const c = buildTaskComment({ authorId: 1, authorType: 'agent', createdAt: minutesAgo(10) });
    expect(canEditComment(c, 1)).toBe(false);
  });

  it('forbids editing a system-authored comment', () => {
    freeze();
    const c = buildTaskComment({ authorId: 1, authorType: 'system', createdAt: minutesAgo(10) });
    expect(canEditComment(c, 1)).toBe(false);
  });

  it('forbids editing a comment older than the 3-hour window', () => {
    freeze();
    const c = buildTaskComment({ authorId: 1, authorType: 'human', createdAt: minutesAgo(181) });
    expect(canEditComment(c, 1)).toBe(false);
  });

  it('allows editing right up to the 3-hour edge', () => {
    freeze();
    const c = buildTaskComment({ authorId: 1, authorType: 'human', createdAt: minutesAgo(179) });
    expect(canEditComment(c, 1)).toBe(true);
  });
});
