import {
  Box,
  Button,
  CircularProgress,
  Grid,
  InputAdornment,
  Snackbar,
  Alert,
  TextField,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useMemo, useState } from 'react';

import { ProjectCard, type IProject } from 'entities/project';
import { Routes } from 'shared/routes';

import { useProjectsQuery } from '../api/projectsApi';

import CreateProjectDialog from './CreateProjectDialog';

const styles = {
  root: {
    minHeight: '100vh',
    backgroundColor: 'background.default',
    padding: '32px',
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: '24px',
  },
  headerText: {},
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
  toolbar: {
    display: 'flex',
    gap: '16px',
    marginBottom: '24px',
  },
  searchField: {
    width: '300px',
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

const ProjectsPage = () => {
  const navigate = useNavigate();
  const { data, isLoading } = useProjectsQuery();
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const projects = useMemo(() => data?.items ?? [], [data?.items]);

  const filteredProjects = useMemo(() => {
    if (!searchQuery.trim()) return projects;
    const query = searchQuery.toLowerCase();
    return projects.filter((p) => p.name.toLowerCase().includes(query) || p.description?.toLowerCase().includes(query));
  }, [projects, searchQuery]);

  const handleProjectClick = (projectId: number) => {
    navigate({ to: Routes.frontend.companyProjectPath(String(projectId)) });
  };

  const handleCreateSuccess = (project: IProject) => {
    setSuccessMessage(`Project "${project.name}" created successfully`);
    // Navigate to the new project
    navigate({ to: Routes.frontend.companyProjectPath(String(project.id)) });
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
        <Box sx={styles.headerText}>
          <Typography sx={styles.title}>Projects</Typography>
          <Typography sx={styles.subtitle}>Select a project to view workflows, artifacts, and tasks</Typography>
        </Box>
        <Button variant="contained" onClick={() => setIsCreateDialogOpen(true)}>
          Create Project
        </Button>
      </Box>

      {/* Search */}
      {projects.length > 0 && (
        <Box sx={styles.toolbar}>
          <TextField
            placeholder="Search projects..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            size="small"
            sx={styles.searchField}
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <span style={{ opacity: 0.5 }}>🔍</span>
                </InputAdornment>
              ),
            }}
          />
        </Box>
      )}

      {/* Projects Grid */}
      {projects.length === 0 ? (
        <Box sx={styles.empty}>
          <Box sx={styles.emptyIcon}>📁</Box>
          <Typography sx={styles.emptyTitle}>No projects yet</Typography>
          <Typography sx={styles.emptyDescription}>
            Create your first project to start organizing your work and collaborate with your team.
          </Typography>
          <Button variant="contained" onClick={() => setIsCreateDialogOpen(true)}>
            Create Your First Project
          </Button>
        </Box>
      ) : filteredProjects.length === 0 ? (
        <Box sx={styles.empty}>
          <Box sx={styles.emptyIcon}>🔍</Box>
          <Typography sx={styles.emptyTitle}>No projects found</Typography>
          <Typography sx={styles.emptyDescription}>No projects match your search. Try a different query.</Typography>
        </Box>
      ) : (
        <Grid container spacing={3} sx={styles.grid}>
          {filteredProjects.map((project: IProject) => (
            <Grid item xs={12} sm={6} lg={4} key={project.id}>
              <ProjectCard project={project} onClick={() => handleProjectClick(project.id)} />
            </Grid>
          ))}
        </Grid>
      )}

      {/* Create Project Dialog */}
      <CreateProjectDialog
        open={isCreateDialogOpen}
        onClose={() => setIsCreateDialogOpen(false)}
        onSuccess={handleCreateSuccess}
      />

      {/* Success Snackbar */}
      <Snackbar
        open={!!successMessage}
        autoHideDuration={4000}
        onClose={() => setSuccessMessage(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert severity="success" onClose={() => setSuccessMessage(null)}>
          {successMessage}
        </Alert>
      </Snackbar>
    </Box>
  );
};

export default ProjectsPage;
