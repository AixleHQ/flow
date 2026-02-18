import DownloadIcon from '@mui/icons-material/Download';
import {
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Tooltip,
  Typography,
} from '@mui/material';
import type { FC } from 'react';

import { useGetCompanyAssetVersionsQuery, useGetProjectAssetVersionsQuery } from '../api/assetsApi';
import type { Asset } from '../lib/types';

interface VersionHistoryDialogProps {
  open: boolean;
  onClose: () => void;
  asset: Asset | null;
  projectId?: number;
}

function formatFileSize(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const VersionHistoryDialog: FC<VersionHistoryDialogProps> = ({ open, onClose, asset, projectId }) => {
  const isProjectContext = !!projectId;

  const { data: companyVersions, isLoading: isLoadingCompany } = useGetCompanyAssetVersionsQuery(asset?.id ?? 0, {
    skip: !open || !asset || isProjectContext,
  });

  const { data: projectVersions, isLoading: isLoadingProject } = useGetProjectAssetVersionsQuery(
    { projectId: projectId ?? 0, assetId: asset?.id ?? 0 },
    { skip: !open || !asset || !isProjectContext },
  );

  const versions = isProjectContext ? projectVersions : companyVersions;
  const isLoading = isProjectContext ? isLoadingProject : isLoadingCompany;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>
        Version History
        {asset && <Typography sx={{ color: 'text.secondaryAlt', fontSize: 14, mt: 0.5 }}>{asset.name}</Typography>}
      </DialogTitle>
      <DialogContent>
        {isLoading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
            <CircularProgress />
          </Box>
        ) : !versions?.length ? (
          <Typography sx={{ color: 'text.secondaryAlt', textAlign: 'center', py: 4 }}>No versions found</Typography>
        ) : (
          <TableContainer>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>Version</TableCell>
                  <TableCell sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>Date</TableCell>
                  <TableCell sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>Size</TableCell>
                  <TableCell sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>Type</TableCell>
                  <TableCell sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>Source</TableCell>
                  <TableCell align="right" sx={{ fontWeight: 600, fontSize: 12, textTransform: 'uppercase' }}>
                    Download
                  </TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {versions.map((v, idx) => (
                  <TableRow key={v.id} hover>
                    <TableCell>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Typography sx={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 13 }}>
                          v{v.version}
                        </Typography>
                        {idx === 0 && (
                          <Chip label="latest" size="small" color="primary" sx={{ height: 20, fontSize: 11 }} />
                        )}
                      </Box>
                    </TableCell>
                    <TableCell>
                      <Typography sx={{ fontSize: 13, color: 'text.secondaryAlt' }}>
                        {formatDate(v.createdAt)}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Typography sx={{ fontFamily: '"JetBrains Mono", monospace', fontSize: 12 }}>
                        {formatFileSize(v.fileSize)}
                      </Typography>
                    </TableCell>
                    <TableCell>
                      <Typography sx={{ fontSize: 12, color: 'text.secondaryAlt' }}>{v.contentType || '—'}</Typography>
                    </TableCell>
                    <TableCell>
                      <Typography sx={{ fontSize: 12, color: 'text.secondaryAlt' }}>{v.source}</Typography>
                    </TableCell>
                    <TableCell align="right">
                      {v.fileUrl ? (
                        <Tooltip title={`Download v${v.version}`}>
                          <IconButton size="small" component="a" href={v.fileUrl} target="_blank" rel="noopener">
                            <DownloadIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                      ) : (
                        <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>—</Typography>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Close</Button>
      </DialogActions>
    </Dialog>
  );
};

export { VersionHistoryDialog };
