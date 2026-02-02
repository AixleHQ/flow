import AddIcon from '@mui/icons-material/Add';
import { Box, Button, CircularProgress, Typography, type SxProps } from '@mui/material';
import { useState, useMemo, type FC } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanyConfigItemsQuery, useGetProjectConfigItemsQuery } from '../api/configItemsApi';
import type { ConfigItem, ConfigItemsFilters } from '../lib/types';

import { ConfigItemFormDialog } from './ConfigItemFormDialog';
import { ConfigItemsFilters as Filters } from './ConfigItemsFilters';
import { ConfigItemsTable } from './ConfigItemsTable';
import { DeleteConfigItemDialog } from './DeleteConfigItemDialog';

interface ConfigItemsPanelProps {
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

export const ConfigItemsPanel: FC<ConfigItemsPanelProps> = ({ projectId }) => {
  const isProjectContext = !!projectId;

  // State
  const [filters, setFilters] = useState<ConfigItemsFilters>({});
  const [searchInput, setSearchInput] = useState('');
  const [isFormDialogOpen, setFormDialogOpen] = useState(false);
  const [editItem, setEditItem] = useState<ConfigItem | null>(null);
  const [deleteItem, setDeleteItem] = useState<ConfigItem | null>(null);

  // Fetch data
  const { data: companyItems, isLoading: isLoadingCompany } = useGetCompanyConfigItemsQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectItems, isLoading: isLoadingProject } = useGetProjectConfigItemsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const items = isProjectContext ? projectItems : companyItems;

  // Debounced search
  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  // Filter items client-side
  const filteredItems = useMemo(() => {
    if (!items) return [];

    return items.filter((item) => {
      // Type filter
      if (filters.itemType && item.itemType !== filters.itemType) {
        return false;
      }

      // Search filter
      if (filters.search) {
        const searchLower = filters.search.toLowerCase();
        return item.name.toLowerCase().includes(searchLower);
      }

      return true;
    });
  }, [items, filters]);

  // Handlers
  const handleEdit = (item: ConfigItem) => {
    setEditItem(item);
    setFormDialogOpen(true);
  };

  const handleDelete = (item: ConfigItem) => {
    setDeleteItem(item);
  };

  const handleFormDialogClose = () => {
    setFormDialogOpen(false);
    setEditItem(null);
  };

  const handleDeleteDialogClose = () => {
    setDeleteItem(null);
  };

  const hasFilters = !!filters.search || !!filters.itemType;

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>
            {isProjectContext ? 'Project Config Items' : 'Company Config Items'}
          </Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage secrets and variables for this project. Project items override company-level items with the same name.'
              : 'Manage company-wide secrets and variables. These are available in all projects.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setFormDialogOpen(true)}>
          Add {isProjectContext ? 'Project ' : ''}Config Item
        </Button>
      </Box>

      {/* Filters */}
      <Filters
        filters={filters}
        onFilterChange={setFilters}
        searchValue={searchInput}
        onSearchChange={handleSearchChange}
      />

      {/* Content */}
      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filteredItems.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No config items match your filters' : 'No config items yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setFormDialogOpen(true)}>
              Add your first config item
            </Button>
          )}
        </Box>
      ) : (
        <ConfigItemsTable
          items={filteredItems}
          isProjectContext={isProjectContext}
          onEdit={handleEdit}
          onDelete={handleDelete}
        />
      )}

      {/* Dialogs */}
      <ConfigItemFormDialog
        open={isFormDialogOpen}
        onClose={handleFormDialogClose}
        projectId={projectId}
        editItem={editItem}
      />

      <DeleteConfigItemDialog
        open={!!deleteItem}
        onClose={handleDeleteDialogClose}
        item={deleteItem}
        projectId={projectId}
      />
    </Box>
  );
};

export default ConfigItemsPanel;
