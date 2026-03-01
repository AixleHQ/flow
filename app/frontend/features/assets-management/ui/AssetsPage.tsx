import AddIcon from '@mui/icons-material/Add';
import SearchIcon from '@mui/icons-material/Search';
import {
  Box,
  Button,
  CircularProgress,
  FormControl,
  InputAdornment,
  InputLabel,
  MenuItem,
  Select,
  TextField,
  Typography,
  type SxProps,
} from '@mui/material';
import { useState, useMemo, type FC, type ReactNode } from 'react';
import { useDebouncedCallback } from 'use-debounce';

import { useGetCompanyAssetsQuery, useGetProjectAssetsQuery } from '../api/assetsApi';
import type { Asset, AssetsFilters } from '../lib/types';

import { AssetPreviewDialog, type AssetPreviewData } from './AssetPreviewDialog';
import { AssetsTable } from './AssetsTable';
import { DeleteAssetDialog } from './DeleteAssetDialog';
import { EditAssetDialog } from './EditAssetDialog';
import { UploadAssetDialog } from './UploadAssetDialog';
import { VersionHistoryDialog } from './VersionHistoryDialog';

interface AssetsPanelProps {
  projectId?: number;
  renderPreview?: (data: AssetPreviewData, onClose: () => void) => ReactNode;
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

export const AssetsPanel: FC<AssetsPanelProps> = ({ projectId, renderPreview }) => {
  const isProjectContext = !!projectId;

  const [filters, setFilters] = useState<AssetsFilters>({});
  const [searchInput, setSearchInput] = useState('');
  const [isUploadOpen, setUploadOpen] = useState(false);
  const [previewAsset, setPreviewAsset] = useState<Asset | null>(null);
  const [editAsset, setEditAsset] = useState<Asset | null>(null);
  const [deleteAsset, setDeleteAsset] = useState<Asset | null>(null);
  const [historyAsset, setHistoryAsset] = useState<Asset | null>(null);

  const { data: companyAssets, isLoading: isLoadingCompany } = useGetCompanyAssetsQuery(undefined, {
    skip: isProjectContext,
  });

  const { data: projectAssets, isLoading: isLoadingProject } = useGetProjectAssetsQuery(projectId!, {
    skip: !isProjectContext,
  });

  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;
  const assets = isProjectContext ? projectAssets : companyAssets;

  const debouncedSetSearch = useDebouncedCallback((value: string) => {
    setFilters((prev) => ({ ...prev, search: value || undefined }));
  }, 300);

  const handleSearchChange = (value: string) => {
    setSearchInput(value);
    debouncedSetSearch(value);
  };

  const folders = useMemo(() => {
    if (!assets) return [];
    const set = new Set(assets.map((a) => a.folder).filter(Boolean) as string[]);
    return Array.from(set).sort();
  }, [assets]);

  const filteredAssets = useMemo(() => {
    if (!assets) return [];
    return assets.filter((asset) => {
      if (filters.search) {
        const q = filters.search.toLowerCase();
        if (!asset.name.toLowerCase().includes(q) && !asset.folder?.toLowerCase().includes(q)) return false;
      }
      if (filters.folder && asset.folder !== filters.folder) return false;
      return true;
    });
  }, [assets, filters]);

  const hasFilters = !!(filters.search || filters.folder);

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Box>
          <Typography sx={styles.title}>{isProjectContext ? 'Project Assets' : 'Company Assets'}</Typography>
          <Typography sx={styles.subtitle}>
            {isProjectContext
              ? 'Manage files for this project. Company assets are also visible here.'
              : 'Manage company-wide assets. These are available in all projects.'}
          </Typography>
        </Box>
        <Button variant="contained" startIcon={<AddIcon />} onClick={() => setUploadOpen(true)}>
          Upload Asset
        </Button>
      </Box>

      <Box sx={styles.filters}>
        <TextField
          placeholder="Search by name or folder..."
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
        {folders.length > 0 && (
          <FormControl size="small" sx={{ minWidth: 140 }}>
            <InputLabel>Folder</InputLabel>
            <Select
              value={filters.folder || ''}
              label="Folder"
              onChange={(e) => setFilters((prev) => ({ ...prev, folder: e.target.value || undefined }))}
            >
              <MenuItem value="">All Folders</MenuItem>
              {folders.map((f) => (
                <MenuItem key={f} value={f}>
                  {f}
                </MenuItem>
              ))}
            </Select>
          </FormControl>
        )}
      </Box>

      {isLoading ? (
        <Box sx={styles.loadingContainer}>
          <CircularProgress />
        </Box>
      ) : filteredAssets.length === 0 ? (
        <Box sx={styles.emptyState}>
          <Typography sx={{ fontSize: 48 }}>📁</Typography>
          <Typography sx={styles.emptyStateText}>
            {hasFilters ? 'No assets match your filters' : 'No assets yet'}
          </Typography>
          {!hasFilters && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={() => setUploadOpen(true)}>
              Upload your first asset
            </Button>
          )}
        </Box>
      ) : (
        <AssetsTable
          assets={filteredAssets}
          isProjectContext={isProjectContext}
          projectId={projectId}
          onPreview={setPreviewAsset}
          onEdit={setEditAsset}
          onDelete={setDeleteAsset}
          onHistory={setHistoryAsset}
        />
      )}

      {renderPreview && (
        <AssetPreviewDialog
          open={!!previewAsset}
          onClose={() => setPreviewAsset(null)}
          asset={previewAsset}
          projectId={projectId}
          renderPreview={renderPreview}
        />
      )}

      <UploadAssetDialog open={isUploadOpen} onClose={() => setUploadOpen(false)} projectId={projectId} />

      <EditAssetDialog open={!!editAsset} onClose={() => setEditAsset(null)} asset={editAsset} projectId={projectId} />

      <DeleteAssetDialog
        open={!!deleteAsset}
        onClose={() => setDeleteAsset(null)}
        asset={deleteAsset}
        projectId={projectId}
      />

      <VersionHistoryDialog
        open={!!historyAsset}
        onClose={() => setHistoryAsset(null)}
        asset={historyAsset}
        projectId={projectId}
      />
    </Box>
  );
};

export default AssetsPanel;
