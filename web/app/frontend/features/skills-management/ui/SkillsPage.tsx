import AddIcon from '@mui/icons-material/Add';
import SearchIcon from '@mui/icons-material/Search';
import { Box, Button, CircularProgress, InputAdornment, TextField, Typography, type SxProps } from '@mui/material';
import { useState, useMemo, type FC } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanySkillsQuery, useGetProjectSkillsQuery } from '../api/skillsApi';
import type { Skill, SkillsFilters } from '../lib/types';

import { DeleteSkillDialog } from './DeleteSkillDialog';
import { SkillFormDialog } from './SkillFormDialog';
import { SkillsTable } from './SkillsTable';

interface SkillsPanelProps {
  projectId?: number; // If provided, shows project context (merged list)
}

const styles = {
  root: {
    p: 3,
  },
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    mb: 3,
  },
  title: {
    fontSize: 24,
    fontWeight: 600,
    color: 'text.primaryAlt',
  },
  subtitle: {
    fontSize: 14,
    color: 'text.secondaryAlt',
    mt: 0.5,
  },
  filters: {
    mb: 3,
  },
  searchField: {
    width: 300,
  },
  loadingContainer: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: 400,
  },
  emptyState: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 300,
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  emptyStateText: {
    color: 'text.secondaryAlt',
    fontSize: 16,
    mt: 2,
  },
} satisfies Record<string, SxProps>;

export const SkillsPanel: FC<SkillsPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;

  // State
  const [filters, setFilters] = useState<SkillsFilters>({});
  const [searchInput, setSearchInput] = useState('');
  const [isFormDialogOpen, setFormDialogOpen] = useState(false);
  const [editSkill, setEditSkill] = useState<Skill | null>(null);
  const [deleteSkill, setDeleteSkill] = useState<Skill | null>(null);

  // Fetch data
  const { data: companySkills, isLoading: isLoadingCompany } = useGetCompanySkillsQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectSkills, isLoading: isLoadingProject } = useGetProjectSkillsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const skills = isProjectContext ? projectSkills : companySkills;

  // Debounced search
  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  // Filter skills client-side
  const filteredSkills = useMemo(() => {
    if (!skills) return [];

    return skills.filter((skill) => {
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        return (
          skill.name.toLowerCase().includes(searchLower) || (skill.title?.toLowerCase().includes(searchLower) ?? false)
        );
      }
      return true;
    });
  }, [skills, filters]);

  // Handlers
  const handleEdit = (skill: Skill) => {
    setEditSkill(skill);
    setFormDialogOpen(true);
  };

  const handleDelete = (skill: Skill) => {
    setDeleteSkill(skill);
  };

  const handleFormDialogClose = () => {
    setFormDialogOpen(false);
    setEditSkill(null);
  };

  const handleDeleteDialogClose = () => {
    setDeleteSkill(null);
  };

  const hasFilters = !!filters.search;

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project Skills' : 'Company Skills'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage skill instructions for this project. Project skills override company skills with the same name.'
              : 'Manage company-wide skill instructions. These are available in all projects.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setFormDialogOpen(true)}>
          Add {isProjectContext ? 'Project ' : ''}Skill
        </Button>
      </Box>

      {/* Search */}
      <Box sx={styles.filters}>
        <TextField
          placeholder="Search by name or title..."
          value={searchInput}
          onChange={(e) => handleSearchChange(e.target.value)}
          size="small"
          sx={styles.searchField}
          InputProps={{
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon />
              </InputAdornment>
            ),
          }}
        />
      </Box>

      {/* Content */}
      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filteredSkills.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>📝</Typography>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No skills match your search' : 'No skills yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setFormDialogOpen(true)}>
              Add your first skill
            </Button>
          )}
        </Box>
      ) : (
        <SkillsTable
          skills={filteredSkills}
          isProjectContext={isProjectContext}
          onEdit={handleEdit}
          onDelete={handleDelete}
        />
      )}

      {/* Dialogs */}
      <SkillFormDialog
        open={isFormDialogOpen}
        onClose={handleFormDialogClose}
        projectId={projectId}
        editSkill={editSkill}
      />

      <DeleteSkillDialog
        open={!!deleteSkill}
        onClose={handleDeleteDialogClose}
        skill={deleteSkill}
        projectId={projectId}
      />
    </Box>
  );
};

export default SkillsPanel;
