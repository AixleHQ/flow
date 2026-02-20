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

import { useGetMcpServersQuery, useGetProjectMcpServersQuery, type McpServer } from 'entities/mcp-server';

import { DeleteMcpServerDialog } from './DeleteMcpServerDialog';
import { McpServerFormDialog } from './McpServerFormDialog';
import { McpServersTable } from './McpServersTable';

interface McpServersPanelProps {
  projectId?: number;
}

interface Filters {
  kind: 'all' | 'internal' | 'custom';
  search?: string;
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

export const McpServersPanel: FC<McpServersPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;

  const [filters, setFilters] = useState<Filters>({ kind: 'all' });
  const [searchInput, setSearchInput] = useState('');
  const [isFormDialogOpen, setFormDialogOpen] = useState(false);
  const [editServer, setEditServer] = useState<McpServer | null>(null);
  const [deleteServer, setDeleteServer] = useState<McpServer | null>(null);

  const { data: companyServers, isLoading: isLoadingCompany } = useGetMcpServersQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectServers, isLoading: isLoadingProject } = useGetProjectMcpServersQuery(String(projectId), {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const servers = isProjectContext ? projectServers : companyServers;

  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  const handleKindFilterChange = (_: unknown, value: 'all' | 'internal' | 'custom' | null) => {
    if (value) {
      setFilters((prev) => ({ ...prev, kind: value }));
    }
  };

  const filteredServers = useMemo(() => {
    if (!servers) return [];

    return servers.filter((server) => {
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        const matchesSearch =
          server.name.toLowerCase().includes(searchLower) || server.displayName.toLowerCase().includes(searchLower);
        if (!matchesSearch) return false;
      }

      if (filters.kind && filters.kind !== 'all') {
        if (server.kind !== filters.kind) return false;
      }

      return true;
    });
  }, [servers, filters]);

  const handleEdit = (server: McpServer) => {
    setEditServer(server);
    setFormDialogOpen(true);
  };

  const handleDelete = (server: McpServer) => {
    setDeleteServer(server);
  };

  const handleFormDialogClose = () => {
    setFormDialogOpen(false);
    setEditServer(null);
  };

  const handleDeleteDialogClose = () => {
    setDeleteServer(null);
  };

  const hasFilters = !!filters.search || (filters.kind && filters.kind !== 'all');

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project MCP Servers' : 'Company MCP Servers'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage MCP servers for this project. Project servers override company servers with the same name.'
              : 'Manage company-wide MCP servers. Configure external tools like Context7, Tavily, etc.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setFormDialogOpen(true)}>
          Add MCP Server
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
          <ToggleButton value="internal">Internal</ToggleButton>
          <ToggleButton value="custom">Custom</ToggleButton>
        </ToggleButtonGroup>
      </Box>

      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filteredServers.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>🔌</Typography>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No MCP servers match your filters' : 'No MCP servers configured'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setFormDialogOpen(true)}>
              Add your first MCP server
            </Button>
          )}
        </Box>
      ) : (
        <McpServersTable
          servers={filteredServers}
          isProjectContext={isProjectContext}
          onEdit={handleEdit}
          onDelete={handleDelete}
        />
      )}

      <McpServerFormDialog
        open={isFormDialogOpen}
        onClose={handleFormDialogClose}
        projectId={projectId}
        editServer={editServer}
      />

      <DeleteMcpServerDialog
        open={!!deleteServer}
        onClose={handleDeleteDialogClose}
        server={deleteServer}
        projectId={projectId}
      />
    </Box>
  );
};

export default McpServersPanel;
