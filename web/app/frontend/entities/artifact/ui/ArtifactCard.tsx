import { Box, Card, IconButton, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import { formatSize } from 'shared/lib';

import { getArtifactType, type IArtifact } from '../model/types';

interface IArtifactCardProps {
  artifact: IArtifact;
  onClick?: () => void;
  onDownload?: () => void;
}

const styles = {
  card: {
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '8px',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'border.strong',
      backgroundColor: 'background.elevated',
    },
  },
  cardAction: {
    padding: '12px 16px',
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  icon: {
    width: '40px',
    height: '40px',
    borderRadius: '8px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'background.elevated',
    fontSize: '20px',
    flexShrink: 0,
  },
  content: {
    flex: 1,
    minWidth: 0,
  },
  name: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    fontFamily: '"JetBrains Mono", monospace',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  provenance: {
    fontSize: '12px',
    color: 'text.secondary',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
  },
  provenanceSeparator: {
    color: 'text.disabled',
  },
  meta: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  size: {
    fontSize: '12px',
    color: 'text.disabled',
    fontFamily: '"JetBrains Mono", monospace',
  },
  actions: {
    display: 'flex',
    gap: '4px',
  },
  actionButton: {
    padding: '6px',
    color: 'text.secondary',
    '&:hover': {
      color: 'text.primary',
      backgroundColor: 'action.hover',
    },
  },
} satisfies Record<string, SxProps<Theme>>;

const getTypeIcon = (type: string): string => {
  const artifactType = getArtifactType(undefined, type);
  switch (artifactType) {
    case 'image':
      return '🖼️';
    case 'code':
      return '💻';
    case 'document':
      return '📄';
    case 'data':
      return '{}';
    default:
      return '📎';
  }
};

const formatRelativeTime = (dateString: string): string => {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString();
};

const ArtifactCard = ({ artifact, onClick, onDownload }: IArtifactCardProps) => {
  const hasProvenance = artifact.workflowName || artifact.stepName || artifact.userName;

  return (
    <Card sx={styles.card} elevation={0}>
      <Box sx={styles.cardAction}>
        {/* Clickable area */}
        <Box
          sx={{ display: 'flex', alignItems: 'center', gap: '12px', flex: 1, minWidth: 0, cursor: 'pointer' }}
          onClick={onClick}
        >
          {/* Icon */}
          <Box sx={styles.icon}>{getTypeIcon(artifact.name)}</Box>

          {/* Content */}
          <Box sx={styles.content}>
            <Typography sx={styles.name}>{artifact.name}</Typography>
            {hasProvenance && (
              <Typography sx={styles.provenance}>
                {artifact.workflowName && (
                  <>
                    <span>{artifact.workflowName}</span>
                    {artifact.stepName && <span style={{ color: 'inherit' }}>→</span>}
                  </>
                )}
                {artifact.stepName && <span>{artifact.stepName}</span>}
                {(artifact.workflowName || artifact.stepName) && artifact.userName && (
                  <span style={{ margin: '0 4px' }}>•</span>
                )}
                {artifact.userName && <span>{artifact.userName}</span>}
                <span style={{ margin: '0 4px' }}>•</span>
                <span>{formatRelativeTime(artifact.createdAt)}</span>
              </Typography>
            )}
          </Box>
        </Box>

        {/* Meta & Actions */}
        <Box sx={styles.meta}>
          {artifact.size && <Typography sx={styles.size}>{formatSize(artifact.size)}</Typography>}
          <Box sx={styles.actions}>
            <Tooltip title="Download">
              <IconButton sx={styles.actionButton} size="small" onClick={onDownload}>
                <span style={{ fontSize: '14px' }}>⬇</span>
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
      </Box>
    </Card>
  );
};

export default ArtifactCard;
