import AddIcon from '@mui/icons-material/Add';
import SearchIcon from '@mui/icons-material/Search';
import {
  Box,
  Button,
  CircularProgress,
  InputAdornment,
  TextField,
  ToggleButton,
  ToggleButtonGroup,
  Typography,
  type SxProps,
} from '@mui/material';
import { useState, useMemo, type FC } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanyToolsQuery, useGetProjectToolsQuery } from '../api/toolsApi';
import type { Tool, ToolsFilters, ToolKind } from '../lib/types';

import { DeleteToolDialog } from './DeleteToolDialog';
import { ToolFormDialog } from './ToolFormDialog';
import { ToolsTable } from './ToolsTable';

interface ToolsPanelProps {
  projectId?: number;
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
    display: 'flex',
    gap: 2,
    mb: 3,
    alignItems: 'center',
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

export const ToolsPanel: FC<ToolsPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;

  const [filters, setFilters] = useState<ToolsFilters>({ kind: 'all' });
  const [searchInput, setSearchInput] = useState('');
  const [isFormDialogOpen, setFormDialogOpen] = useState(false);
  const [editTool, setEditTool] = useState<Tool | null>(null);
  const [deleteTool, setDeleteTool] = useState<Tool | null>(null);

  const { data: companyTools, isLoading: isLoadingCompany } = useGetCompanyToolsQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectTools, isLoading: isLoadingProject } = useGetProjectToolsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const tools = isProjectContext ? projectTools : companyTools;

  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  const handleKindFilterChange = (_: unknown, value: ToolKind | 'all' | null) => {
    if (value) {
      setFilters((prev) => ({ ...prev, kind: value }));
    }
  };

  const filteredTools = useMemo(() => {
    if (!tools) return [];

    return tools.filter((tool) => {
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        const matchesSearch =
          tool.name.toLowerCase().includes(searchLower) || tool.displayName.toLowerCase().includes(searchLower);
        if (!matchesSearch) return false;
      }

      if (filters.kind && filters.kind !== 'all') {
        if (tool.kind !== filters.kind) return false;
      }

      return true;
    });
  }, [tools, filters]);

  const handleEdit = (tool: Tool) => {
    setEditTool(tool);
    setFormDialogOpen(true);
  };

  const handleDelete = (tool: Tool) => {
    setDeleteTool(tool);
  };

  const handleFormDialogClose = () => {
    setFormDialogOpen(false);
    setEditTool(null);
  };

  const handleDeleteDialogClose = () => {
    setDeleteTool(null);
  };

  const hasFilters = !!filters.search || (filters.kind && filters.kind !== 'all');

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project Tools' : 'Company Tools'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage tools for this project. Project tools override company tools with the same name.'
              : 'Manage company-wide tools. System tools are platform-provided and read-only.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setFormDialogOpen(true)}>
          Add {isProjectContext ? 'Project ' : ''}Tool
        </Button>
      </Box>

      <Box sx={styles.filters}>
        <TextField
          placeholder="Search by name..."
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
        <ToggleButtonGroup value={filters.kind} exclusive onChange={handleKindFilterChange} size="small">
          <ToggleButton value="all">All</ToggleButton>
          <ToggleButton value="system">System</ToggleButton>
          <ToggleButton value="custom">Custom</ToggleButton>
        </ToggleButtonGroup>
      </Box>

      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filteredTools.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>🔧</Typography>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No tools match your filters' : 'No tools yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setFormDialogOpen(true)}>
              Add your first tool
            </Button>
          )}
        </Box>
      ) : (
        <ToolsTable
          tools={filteredTools}
          isProjectContext={isProjectContext}
          onEdit={handleEdit}
          onDelete={handleDelete}
        />
      )}

      <ToolFormDialog
        open={isFormDialogOpen}
        onClose={handleFormDialogClose}
        projectId={projectId}
        editTool={editTool}
      />

      <DeleteToolDialog open={!!deleteTool} onClose={handleDeleteDialogClose} tool={deleteTool} projectId={projectId} />
    </Box>
  );
};

export default ToolsPanel;
