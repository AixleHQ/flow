import type TaskComment from 'types/generated/TaskComment';

// Mirrors the server rule (TaskComment#editable_by? / CommentsPolicy#update?,
// window TaskComment::EDIT_WINDOW): a comment is editable only by its own author,
// only when human-authored, and only while younger than three hours. The server
// is the source of truth (a 403 on an expired or unauthorized edit); this helper
// only decides whether the Edit affordance is offered.
export const COMMENT_EDIT_WINDOW_MS = 3 * 60 * 60 * 1000;

export function canEditComment(c: TaskComment, currentUserId: number): boolean {
  return (
    c.authorType === 'human' &&
    c.authorId === currentUserId &&
    Date.now() - new Date(c.createdAt).getTime() < COMMENT_EDIT_WINDOW_MS
  );
}
