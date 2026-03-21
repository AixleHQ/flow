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
    height: '100%',
    width: '100%',
    display: 'flex',
    flexDirection: 'column',
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
    flex: 1,
    width: '100%',
    minHeight: 0,
  },
  header: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    width: '100%',
    marginBottom: '12px',
    minHeight: '28px',
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
    display: '-webkit-box',
    WebkitLineClamp: 2,
    WebkitBoxOrient: 'vertical',
    overflow: 'hidden',
  },
  descriptionSlot: {
    width: '100%',
    minHeight: '52px',
    marginBottom: '16px',
  },
  footer: {
    width: '100%',
    marginTop: 'auto',
  },
  stats: {
    display: 'flex',
    gap: '16px',
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
    minHeight: '18px',
    lineHeight: '18px',
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
  return (
    <Card sx={styles.card} elevation={0}>
      <CardActionArea sx={styles.cardAction} onClick={onClick}>
        <Box sx={styles.header}>
          <Box>
            <Typography sx={styles.title}>{project.name}</Typography>
          </Box>
          {project.state === 'active' && project.collaboratorsCount > 0 && (
            <Chip
              label={`${project.collaboratorsCount} collaborator${project.collaboratorsCount > 1 ? 's' : ''}`}
              size="small"
              sx={styles.chip}
            />
          )}
        </Box>

        <Box sx={styles.descriptionSlot}>
          {project.description ? <Typography sx={styles.description}>{project.description}</Typography> : null}
        </Box>

        <Box sx={styles.footer}>
          <Box sx={styles.stats}>
            <Box sx={styles.stat}>
              <Typography sx={styles.statValue}>{project.collaboratorsCount}</Typography>
              <Typography sx={styles.statLabel}>Collaborators</Typography>
            </Box>
          </Box>
          <Typography
            sx={{
              ...styles.lastActivity,
              visibility: project.lastActivityAt ? 'visible' : 'hidden',
            }}
          >
            Last activity {formatRelativeTime(project.lastActivityAt ?? undefined)}
          </Typography>
        </Box>
      </CardActionArea>
    </Card>
  );
};

export default ProjectCard;
