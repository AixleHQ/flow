import { Box, CircularProgress, Grid, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';

import { ProjectCard, type IProject } from 'entities/project';

import { useProjectsQuery } from '../api/projectsApi';

const styles = {
  root: {
    minHeight: '100vh',
    backgroundColor: 'background.default',
    padding: '32px',
  },
  header: {
    marginBottom: '32px',
  },
  title: {
    fontSize: '32px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '8px',
  },
  subtitle: {
    fontSize: '16px',
    color: 'text.secondary',
  },
  grid: {
    marginTop: '24px',
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '400px',
  },
  empty: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '400px',
    gap: '16px',
  },
  emptyIcon: {
    fontSize: '48px',
    opacity: 0.5,
  },
  emptyTitle: {
    fontSize: '20px',
    fontWeight: 500,
    color: 'text.primary',
  },
  emptyDescription: {
    fontSize: '14px',
    color: 'text.secondary',
    textAlign: 'center',
    maxWidth: '400px',
  },
} satisfies Record<string, SxProps<Theme>>;

// Mock data for development - remove when API is ready
const mockProjects: IProject[] = [
  {
    id: '1',
    name: 'Palad Platform',
    description: 'AI coding agents orchestration platform with workflow automation',
    companyId: '1',
    artifactsCount: 42,
    tasksCount: 15,
    activeTasksCount: 3,
    workflowsCount: 8,
    lastActivityAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
  },
  {
    id: '2',
    name: 'Mobile App',
    description: 'React Native mobile application for iOS and Android',
    companyId: '1',
    artifactsCount: 18,
    tasksCount: 7,
    activeTasksCount: 0,
    workflowsCount: 3,
    lastActivityAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
  },
  {
    id: '3',
    name: 'Documentation Site',
    description: 'Technical documentation and API reference',
    companyId: '1',
    artifactsCount: 5,
    tasksCount: 2,
    activeTasksCount: 1,
    workflowsCount: 2,
    lastActivityAt: new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString(),
    createdAt: new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString(),
    updatedAt: new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString(),
  },
];

const ProjectsPage = () => {
  const navigate = useNavigate();
  const { data, isLoading } = useProjectsQuery();

  // Use mock data if API returns empty or fails
  const projects = data?.data?.length ? data.data : mockProjects;

  const handleProjectClick = (projectId: string) => {
    navigate({ to: '/projects/$projectId', params: { projectId } });
  };

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <CircularProgress />
        </Box>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Projects</Typography>
        <Typography sx={styles.subtitle}>
          Select a project to view workflows, artifacts, and tasks
        </Typography>
      </Box>

      {/* Projects Grid */}
      {projects.length === 0 ? (
        <Box sx={styles.empty}>
          <Box sx={styles.emptyIcon}>📁</Box>
          <Typography sx={styles.emptyTitle}>No projects yet</Typography>
          <Typography sx={styles.emptyDescription}>
            You don't have access to any projects. Ask your team admin to invite you to a project.
          </Typography>
        </Box>
      ) : (
        <Grid container spacing={3} sx={styles.grid}>
          {projects.map((project) => (
            <Grid item xs={12} sm={6} lg={4} key={project.id}>
              <ProjectCard project={project} onClick={() => handleProjectClick(project.id)} />
            </Grid>
          ))}
        </Grid>
      )}
    </Box>
  );
};

export default ProjectsPage;
