import SendIcon from '@mui/icons-material/Send';
import { Autocomplete, Avatar, Box, Button, Chip, MenuItem, TextField, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useCallback, useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

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
  body: {
    fontSize: '13px',
    lineHeight: 1.5,
    '& p': { margin: 0, marginBottom: '4px', fontSize: '13px', lineHeight: 1.5, color: 'text.primary' },
    '& p:last-child': { marginBottom: 0 },
    '& strong': { fontWeight: 600 },
    '& em': { fontStyle: 'italic' },
    '& code': {
      backgroundColor: 'action.selected',
      padding: '1px 4px',
      borderRadius: '3px',
      fontSize: '12px',
      fontFamily: '"JetBrains Mono", monospace',
    },
    '& pre': {
      backgroundColor: 'action.selected',
      padding: '8px 12px',
      borderRadius: '6px',
      overflow: 'auto',
      fontSize: '12px',
      fontFamily: '"JetBrains Mono", monospace',
      lineHeight: 1.5,
      margin: '4px 0',
    },
    '& pre code': { backgroundColor: 'transparent', padding: 0 },
    '& ul, & ol': { marginLeft: '20px', marginBottom: '4px', marginTop: '2px' },
    '& li': { fontSize: '13px', lineHeight: 1.5, color: 'text.primary' },
    '& a': { color: 'primary.main', textDecoration: 'underline' },
    '& blockquote': {
      borderLeft: '3px solid',
      borderColor: 'divider',
      paddingLeft: '8px',
      margin: '4px 0',
      color: 'text.secondary',
      fontStyle: 'italic',
    },
  },
  tags: { display: 'flex', gap: 0.5, mt: 0.75 },
  tagChip: { height: 18, fontSize: '10px' },
  form: {
    display: 'flex',
    flexDirection: 'column',
    gap: 1,
    borderBottom: '1px solid',
    borderColor: 'divider',
    pb: 2,
    mb: 2,
  },
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

      <Box sx={styles.commentList}>
        {comments.map((comment: TaskComment) => (
          <Box key={comment.id} sx={styles.comment}>
            <Box sx={styles.commentHeader}>
              <Avatar sx={{ width: 22, height: 22, fontSize: '10px' }}>{comment.authorName?.[0] || 'U'}</Avatar>
              <Typography sx={styles.authorName}>{comment.authorName}</Typography>
              <Chip label={comment.authorType} size="small" sx={styles.authorBadge} />
              <Typography sx={styles.timestamp}>{new Date(comment.createdAt).toLocaleString()}</Typography>
            </Box>
            <Box sx={styles.body}>
              <Markdown remarkPlugins={[remarkGfm]}>{comment.body}</Markdown>
            </Box>
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
    </Box>
  );
};
