import SendIcon from '@mui/icons-material/Send';
import { Autocomplete, Avatar, Box, Button, Chip, MenuItem, TextField, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useCallback, useState } from 'react';

import { COMMENT_TAG_SUGGESTIONS } from 'entities/board-task';
import type { TaskComment } from 'entities/board-task';

import { useCreateCommentMutation, useGetTaskCommentsQuery } from '../api/boardApi';

interface CommentsTabProps {
  taskId: number;
  projectId: number;
}

const styles = {
  filters: { display: 'flex', gap: 1, mb: 2 },
  commentList: { display: 'flex', flexDirection: 'column', gap: 1.5, mb: 2 },
  comment: { p: 1.5, backgroundColor: 'action.hover', borderRadius: '8px' },
  commentHeader: { display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 },
  authorName: { fontSize: '13px', fontWeight: 600 },
  authorBadge: { height: 18, fontSize: '10px' },
  timestamp: { fontSize: '11px', color: 'text.disabled', ml: 'auto' },
  body: { fontSize: '13px', whiteSpace: 'pre-wrap', lineHeight: 1.5 },
  tags: { display: 'flex', gap: 0.5, mt: 0.75 },
  tagChip: { height: 18, fontSize: '10px' },
  form: { display: 'flex', flexDirection: 'column', gap: 1, borderTop: '1px solid', borderColor: 'divider', pt: 2 },
} satisfies Record<string, SxProps<Theme>>;

const AUTHOR_TYPES = ['all', 'human', 'agent', 'system'] as const;

export const CommentsTab = ({ taskId, projectId }: CommentsTabProps) => {
  const [tagFilter, setTagFilter] = useState('');
  const [authorTypeFilter, setAuthorTypeFilter] = useState('all');
  const [body, setBody] = useState('');
  const [tags, setTags] = useState<string[]>([]);

  const { data: comments = [] } = useGetTaskCommentsQuery({
    projectId,
    taskId,
    tag: tagFilter || undefined,
    authorType: authorTypeFilter === 'all' ? undefined : authorTypeFilter,
  });
  const [createComment, { isLoading }] = useCreateCommentMutation();

  const handleSubmit = useCallback(async () => {
    if (!body.trim()) return;
    await createComment({ projectId, taskId, body: body.trim(), tags });
    setBody('');
    setTags([]);
  }, [body, tags, createComment, projectId, taskId]);

  return (
    <Box>
      <Box sx={styles.filters}>
        <TextField
          select
          size="small"
          label="Author"
          value={authorTypeFilter}
          onChange={(e) => setAuthorTypeFilter(e.target.value)}
          sx={{ minWidth: 100 }}
        >
          {AUTHOR_TYPES.map((t) => (
            <MenuItem key={t} value={t}>
              {t}
            </MenuItem>
          ))}
        </TextField>
        <TextField
          size="small"
          label="Filter by tag"
          value={tagFilter}
          onChange={(e) => setTagFilter(e.target.value)}
          sx={{ flex: 1 }}
        />
      </Box>

      <Box sx={styles.commentList}>
        {comments.map((comment: TaskComment) => (
          <Box key={comment.id} sx={styles.comment}>
            <Box sx={styles.commentHeader}>
              <Avatar sx={{ width: 22, height: 22, fontSize: '10px' }}>{comment.authorName?.[0] || 'U'}</Avatar>
              <Typography sx={styles.authorName}>{comment.authorName}</Typography>
              <Chip label={comment.authorType} size="small" sx={styles.authorBadge} />
              <Typography sx={styles.timestamp}>{new Date(comment.createdAt).toLocaleString()}</Typography>
            </Box>
            <Typography sx={styles.body}>{comment.body}</Typography>
            {comment.tags.length > 0 && (
              <Box sx={styles.tags}>
                {comment.tags.map((tag) => (
                  <Chip key={tag} label={tag} size="small" variant="outlined" sx={styles.tagChip} />
                ))}
              </Box>
            )}
          </Box>
        ))}
        {comments.length === 0 && (
          <Typography sx={{ color: 'text.disabled', fontSize: '13px', textAlign: 'center', py: 3 }}>
            No comments yet
          </Typography>
        )}
      </Box>

      <Box sx={styles.form}>
        <TextField
          multiline
          minRows={2}
          size="small"
          placeholder="Write a comment..."
          value={body}
          onChange={(e) => setBody(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && e.metaKey && handleSubmit()}
        />
        <Autocomplete
          multiple
          freeSolo
          size="small"
          options={[...COMMENT_TAG_SUGGESTIONS]}
          value={tags}
          onChange={(_, val) => setTags(val)}
          renderTags={(value, getTagProps) =>
            value.map((tag, idx) => <Chip {...getTagProps({ index: idx })} key={tag} label={tag} size="small" />)
          }
          renderInput={(params) => <TextField {...params} placeholder="Tags..." />}
        />
        <Button
          variant="contained"
          size="small"
          endIcon={<SendIcon />}
          onClick={handleSubmit}
          disabled={!body.trim() || isLoading}
        >
          Send
        </Button>
      </Box>
    </Box>
  );
};
