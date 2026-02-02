import AddIcon from '@mui/icons-material/Add';
import SearchIcon from '@mui/icons-material/Search';
import { Box, Button, CircularProgress, InputAdornment, TextField, Typography, type SxProps } from '@mui/material';
import { useState, useMemo, type FC } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanyAgentsQuery, useGetProjectAgentsQuery } from '../api/agentsApi';
import type { Agent, AgentsFilters } from '../lib/types';

import { AgentFormDialog } from './AgentFormDialog';
import { AgentsTable } from './AgentsTable';
import { DeleteAgentDialog } from './DeleteAgentDialog';

interface AgentsPanelProps {
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

export const AgentsPanel: FC<AgentsPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;

  // State
  const [filters, setFilters] = useState<AgentsFilters>({});
  const [searchInput, setSearchInput] = useState('');
  const [isFormDialogOpen, setFormDialogOpen] = useState(false);
  const [editAgent, setEditAgent] = useState<Agent | null>(null);
  const [deleteAgent, setDeleteAgent] = useState<Agent | null>(null);

  // Fetch data
  const { data: companyAgents, isLoading: isLoadingCompany } = useGetCompanyAgentsQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectAgents, isLoading: isLoadingProject } = useGetProjectAgentsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const agents = isProjectContext ? projectAgents : companyAgents;

  // Debounced search
  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  // Filter agents client-side
  const filteredAgents = useMemo(() => {
    if (!agents) return [];

    return agents.filter((agent) => {
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        return agent.name.toLowerCase().includes(searchLower) || agent.title.toLowerCase().includes(searchLower);
      }
      return true;
    });
  }, [agents, filters]);

  // Handlers
  const handleEdit = (agent: Agent) => {
    setEditAgent(agent);
    setFormDialogOpen(true);
  };

  const handleDelete = (agent: Agent) => {
    setDeleteAgent(agent);
  };

  const handleFormDialogClose = () => {
    setFormDialogOpen(false);
    setEditAgent(null);
  };

  const handleDeleteDialogClose = () => {
    setDeleteAgent(null);
  };

  const hasFilters = !!filters.search;

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project Agents' : 'Company Agents'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage agent configurations for this project. Project agents override company agents with the same name.'
              : 'Manage company-wide agent configurations. These are available in all projects.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setFormDialogOpen(true)}>
          Add {isProjectContext ? 'Project ' : ''}Agent
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
      ) : filteredAgents.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>🤖</Typography>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No agents match your search' : 'No agents yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setFormDialogOpen(true)}>
              Add your first agent
            </Button>
          )}
        </Box>
      ) : (
        <AgentsTable
          agents={filteredAgents}
          isProjectContext={isProjectContext}
          onEdit={handleEdit}
          onDelete={handleDelete}
        />
      )}

      {/* Dialogs */}
      <AgentFormDialog
        open={isFormDialogOpen}
        onClose={handleFormDialogClose}
        projectId={projectId}
        editAgent={editAgent}
      />

      <DeleteAgentDialog
        open={!!deleteAgent}
        onClose={handleDeleteDialogClose}
        agent={deleteAgent}
        projectId={projectId}
      />
    </Box>
  );
};

export default AgentsPanel;
