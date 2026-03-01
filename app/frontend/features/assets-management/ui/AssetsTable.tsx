import DeleteIcon from '@mui/icons-material/Delete';
import DownloadIcon from '@mui/icons-material/Download';
import EditIcon from '@mui/icons-material/Edit';
import FolderIcon from '@mui/icons-material/Folder';
import HistoryIcon from '@mui/icons-material/History';
import VisibilityIcon from '@mui/icons-material/Visibility';
import {
  Box,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Tooltip,
  Typography,
  type SxProps,
} from '@mui/material';
import type { FC } from 'react';

import { Routes } from 'shared/routes';

import type { Asset } from '../lib/types';

import { AssetScopeBadge } from './AssetScopeBadge';

interface AssetsTableProps {
  assets: Asset[];
  isProjectContext: boolean;
  projectId?: number;
  onPreview: (asset: Asset) => void;
  onEdit: (asset: Asset) => void;
  onDelete: (asset: Asset) => void;
  onHistory: (asset: Asset) => void;
}

const styles = {
  tableContainer: {
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  tableHead: {
    backgroundColor: 'background.base',
  },
  tableHeadCell: {
    color: 'text.secondaryAlt',
    fontWeight: 600,
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  tableCell: {
    color: 'text.primaryAlt',
    fontSize: 14,
  },
  nameCell: {
    fontWeight: 500,
    fontSize: 13,
  },
  folderChip: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 0.5,
    color: 'text.secondaryAlt',
    fontSize: 12,
  },
  sizeCell: {
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: 12,
    color: 'text.secondaryAlt',
  },
} satisfies Record<string, SxProps | object>;

function formatFileSize(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

const AssetsTable: FC<AssetsTableProps> = ({
  assets,
  isProjectContext,
  projectId,
  onPreview,
  onEdit,
  onDelete,
  onHistory,
}) => {
  const canEdit = (asset: Asset): boolean => {
    if (isProjectContext) return asset.scopeType === 'Project';
    return true;
  };

  const getDownloadUrl = (asset: Asset): string => {
    if (isProjectContext && projectId) {
      return Routes.backend.downloadApiV1CompanyProjectAssetPath(projectId, asset.id);
    }
    return Routes.backend.downloadApiV1CompanyAssetPath(asset.id);
  };

  return (
    <TableContainer sx={styles.tableContainer}>
      <Table>
        <TableHead sx={styles.tableHead}>
          <TableRow>
            <TableCell sx={styles.tableHeadCell}>Name</TableCell>
            <TableCell sx={styles.tableHeadCell}>Folder</TableCell>
            <TableCell sx={styles.tableHeadCell}>Size</TableCell>
            <TableCell sx={styles.tableHeadCell}>Version</TableCell>
            {isProjectContext && <TableCell sx={styles.tableHeadCell}>Scope</TableCell>}
            <TableCell sx={styles.tableHeadCell}>Date</TableCell>
            <TableCell sx={styles.tableHeadCell} align="right">
              Actions
            </TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {assets.map((asset) => (
            <TableRow key={`${asset.scopeType}-${asset.id}`} hover>
              <TableCell sx={styles.tableCell}>
                <Typography sx={styles.nameCell}>{asset.name}</Typography>
                {asset.latestVersion?.source && asset.latestVersion.source !== 'upload' && (
                  <Typography sx={{ fontSize: 11, color: 'text.secondaryAlt', mt: 0.25 }}>
                    {asset.latestVersion.source}
                  </Typography>
                )}
              </TableCell>
              <TableCell sx={styles.tableCell}>
                {asset.folder ? (
                  <Box sx={styles.folderChip}>
                    <FolderIcon sx={{ fontSize: 14 }} />
                    {asset.folder}
                  </Box>
                ) : (
                  <Typography sx={{ color: 'text.disabled', fontSize: 13 }}>—</Typography>
                )}
              </TableCell>
              <TableCell sx={styles.tableCell}>
                <Typography sx={styles.sizeCell}>{formatFileSize(asset.latestVersion?.fileSize ?? null)}</Typography>
              </TableCell>
              <TableCell sx={styles.tableCell}>
                <Typography sx={{ fontSize: 13, fontFamily: '"JetBrains Mono", monospace' }}>
                  v{asset.latestVersion?.version ?? 1}
                  {asset.versionsCount > 1 && (
                    <Typography component="span" sx={{ fontSize: 11, color: 'text.secondaryAlt', ml: 0.5 }}>
                      ({asset.versionsCount})
                    </Typography>
                  )}
                </Typography>
              </TableCell>
              {isProjectContext && (
                <TableCell sx={styles.tableCell}>
                  <AssetScopeBadge indicator={asset.scopeIndicator} />
                </TableCell>
              )}
              <TableCell sx={styles.tableCell}>
                <Typography sx={{ fontSize: 13, color: 'text.secondaryAlt' }}>{formatDate(asset.updatedAt)}</Typography>
              </TableCell>
              <TableCell sx={styles.tableCell} align="right">
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 0.5 }}>
                  {asset.latestVersion && (
                    <Tooltip title="Preview">
                      <IconButton size="small" onClick={() => onPreview(asset)}>
                        <VisibilityIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {asset.versionsCount > 0 && (
                    <Tooltip title="Version history">
                      <IconButton size="small" onClick={() => onHistory(asset)}>
                        <HistoryIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {asset.latestVersion && (
                    <Tooltip title="Download">
                      <IconButton
                        size="small"
                        component="a"
                        href={getDownloadUrl(asset)}
                        target="_blank"
                        rel="noopener"
                      >
                        <DownloadIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canEdit(asset) && (
                    <Tooltip title="Edit">
                      <IconButton size="small" onClick={() => onEdit(asset)}>
                        <EditIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canEdit(asset) && (
                    <Tooltip title="Delete">
                      <IconButton size="small" onClick={() => onDelete(asset)} sx={{ color: 'error.main' }}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                </Box>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
};

export { AssetsTable };
