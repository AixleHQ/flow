import { Box, Button, TextField, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useEffect, useState } from 'react';

import { useProjectQuery, useUpdateProjectMutation } from '../api/projectApi';

interface SettingsTabProps {
  projectId: string;
}

const styles = {
  container: {
    padding: '32px',
    maxWidth: '700px',
  },
  sectionTitle: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '8px',
  },
  sectionDescription: {
    fontSize: '14px',
    color: 'text.secondary',
    marginBottom: '24px',
  },
  card: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  formField: {
    marginBottom: '20px',
  },
  label: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '8px',
  },
  saveButton: {
    minWidth: '120px',
    textTransform: 'none',
  },
} satisfies Record<string, SxProps<Theme>>;

const SettingsTab = ({ projectId }: SettingsTabProps) => {
  const { enqueueSnackbar } = useSnackbar();
  const { data: projectData } = useProjectQuery(projectId);
  const [updateProject, { isLoading: isSaving }] = useUpdateProjectMutation();

  const project = projectData?.data;

  const [name, setName] = useState('');
  const [description, setDescription] = useState('');

  useEffect(() => {
    if (project) {
      setName(project.name);
      setDescription(project.description || '');
    }
  }, [project]);

  const isDirty = project && (name !== project.name || description !== (project.description || ''));

  const handleSave = async () => {
    try {
      await updateProject({ projectId, project: { name: name.trim(), description: description.trim() } }).unwrap();
      enqueueSnackbar('Project settings saved', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to save settings', { variant: 'error' });
    }
  };

  return (
    <Box sx={styles.container}>
      <Typography sx={styles.sectionTitle}>Project Settings</Typography>
      <Typography sx={styles.sectionDescription}>Configure your project name and description.</Typography>

      <Box sx={styles.card}>
        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Project Name</Typography>
          <TextField
            fullWidth
            size="small"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Enter project name"
          />
        </Box>

        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Description</Typography>
          <TextField
            fullWidth
            multiline
            minRows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Enter project description"
          />
        </Box>

        <Box sx={{ display: 'flex', justifyContent: 'flex-end', marginTop: '24px' }}>
          <Button
            variant="contained"
            sx={styles.saveButton}
            onClick={handleSave}
            disabled={!isDirty || !name.trim() || isSaving}
          >
            {isSaving ? 'Saving...' : 'Save Changes'}
          </Button>
        </Box>
      </Box>
    </Box>
  );
};

export default SettingsTab;
