import { Box, Card, CardActionArea, Chip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import type { IProject } from '../model/types';

interface IProjectCardProps {
  project: IProject;
  onClick?: () => void;
}

const styles = {
  card: {
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '12px',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
      transform: 'translateY(-2px)',
      boxShadow: '0 8px 24px rgba(0, 0, 0, 0.3)',
    },
  },
  cardAction: {
    padding: '20px',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'flex-start',
    height: '100%',
  },
  header: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    width: '100%',
    marginBottom: '12px',
  },
  title: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
  },
  description: {
    fontSize: '14px',
    color: 'text.secondary',
    marginBottom: '16px',
    display: '-webkit-box',
    WebkitLineClamp: 2,
    WebkitBoxOrient: 'vertical',
    overflow: 'hidden',
  },
  stats: {
    display: 'flex',
    gap: '16px',
    marginTop: 'auto',
    width: '100%',
  },
  stat: {
    display: 'flex',
    flexDirection: 'column',
    gap: '2px',
  },
  statValue: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    fontFamily: '"JetBrains Mono", monospace',
  },
  statLabel: {
    fontSize: '11px',
    color: 'text.disabled',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  chip: {
    height: '24px',
    fontSize: '12px',
  },
  lastActivity: {
    fontSize: '12px',
    color: 'text.disabled',
    marginTop: '12px',
  },
} satisfies Record<string, SxProps<Theme>>;

const formatRelativeTime = (dateString?: string): string => {
  if (!dateString) return '';

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

const ProjectCard = ({ project, onClick }: IProjectCardProps) => {
  const hasActiveTasks = project.activeTasksCount > 0;

  return (
    <Card sx={styles.card} elevation={0}>
      <CardActionArea sx={styles.cardAction} onClick={onClick}>
        <Box sx={styles.header}>
          <Box>
            <Typography sx={styles.title}>{project.name}</Typography>
          </Box>
          {hasActiveTasks && (
            <Chip label={`${project.activeTasksCount} active`} color="primary" size="small" sx={styles.chip} />
          )}
        </Box>

        {project.description && <Typography sx={styles.description}>{project.description}</Typography>}

        <Box sx={styles.stats}>
          <Box sx={styles.stat}>
            <Typography sx={styles.statValue}>{project.artifactsCount}</Typography>
            <Typography sx={styles.statLabel}>Artifacts</Typography>
          </Box>
          <Box sx={styles.stat}>
            <Typography sx={styles.statValue}>{project.tasksCount}</Typography>
            <Typography sx={styles.statLabel}>Tasks</Typography>
          </Box>
          <Box sx={styles.stat}>
            <Typography sx={styles.statValue}>{project.workflowsCount}</Typography>
            <Typography sx={styles.statLabel}>Workflows</Typography>
          </Box>
        </Box>

        {project.lastActivityAt && (
          <Typography sx={styles.lastActivity}>Last activity {formatRelativeTime(project.lastActivityAt)}</Typography>
        )}
      </CardActionArea>
    </Card>
  );
};

export default ProjectCard;
