import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  Paper,
  Snackbar,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import { useCallback, useState } from 'react';

import {
  useExportAllAssetsMutation,
  useExportAssetMutation,
  useGetWorkflowRunAssetsQuery,
} from '../api/workflowRunsApi';
import type { WorkflowRunAsset } from '../lib/types';

interface Props {
  projectId: number;
  runId: number;
  stepNameMap?: Record<number, string>;
}

function humanFileSize(bytes: number | null): string {
  if (!bytes) return '--';
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

type ExportTarget = { type: 'single'; asset: WorkflowRunAsset } | { type: 'all' };

export const WorkflowAssetsReview = ({ projectId, runId, stepNameMap = {} }: Props) => {
  const { data: assets, isLoading } = useGetWorkflowRunAssetsQuery({ projectId, runId });
  const [exportAsset] = useExportAssetMutation();
  const [exportAll, { isLoading: exportingAll }] = useExportAllAssetsMutation();
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [exportTarget, setExportTarget] = useState<ExportTarget | null>(null);
  const [folder, setFolder] = useState('');
  const [exporting, setExporting] = useState(false);

  const openExportDialog = useCallback((target: ExportTarget) => {
    setExportTarget(target);
    setFolder('');
  }, []);

  const handleConfirmExport = useCallback(async () => {
    if (!exportTarget) return;
    setExporting(true);
    const folderParam = folder.trim() || undefined;
    try {
      if (exportTarget.type === 'single') {
        await exportAsset({
          projectId,
          runId,
          assetId: exportTarget.asset.id,
          folder: folderParam,
        }).unwrap();
        setSnackbar(`Exported "${exportTarget.asset.name}" to project assets`);
      } else {
        const result = await exportAll({ projectId, runId, folder: folderParam }).unwrap();
        setSnackbar(`Exported ${result.exportedCount} artifacts to project assets`);
      }
    } catch {
      setSnackbar('Export failed');
    } finally {
      setExporting(false);
      setExportTarget(null);
    }
  }, [exportTarget, folder, exportAsset, exportAll, projectId, runId]);

  if (isLoading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
        <CircularProgress size={24} />
      </Box>
    );
  }

  if (!assets || assets.length === 0) {
    return (
      <Box sx={{ p: 3, textAlign: 'center' }}>
        <Typography sx={{ color: 'text.secondary', fontSize: '13px' }}>No artifacts produced</Typography>
      </Box>
    );
  }

  const grouped = assets.reduce<Record<string, WorkflowRunAsset[]>>((acc, asset) => {
    const key = asset.producedByStepRunId?.toString() ?? 'manual';
    if (!acc[key]) acc[key] = [];
    acc[key].push(asset);
    return acc;
  }, {});

  const stepLabel = (key: string) => {
    if (key === 'manual') return 'Manual';
    const id = Number(key);
    return stepNameMap[id] ?? `Step Run #${key}`;
  };

  return (
    <Box sx={{ p: 2 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Typography sx={{ fontSize: '14px', fontWeight: 600 }}>Workflow Artifacts ({assets.length})</Typography>
        <Button
          size="small"
          variant="outlined"
          onClick={() => openExportDialog({ type: 'all' })}
          disabled={exportingAll}
        >
          Promote All to Project
        </Button>
      </Box>

      {Object.entries(grouped).map(([stepKey, stepAssets]) => (
        <Paper key={stepKey} variant="outlined" sx={{ mb: 2, overflow: 'hidden' }}>
          <Box
            sx={{
              px: 2,
              py: 1,
              backgroundColor: 'background.elevated',
              borderBottom: '1px solid',
              borderColor: 'divider',
              display: 'flex',
              alignItems: 'center',
              gap: 1,
            }}
          >
            <Typography sx={{ fontSize: '12px', fontWeight: 600, color: 'text.secondary' }}>
              {stepLabel(stepKey)}
            </Typography>
            <Chip
              label={`${stepAssets.length} file${stepAssets.length > 1 ? 's' : ''}`}
              size="small"
              sx={{ height: 18, fontSize: '10px' }}
            />
          </Box>
          {stepAssets.map((asset) => (
            <Box
              key={asset.id}
              sx={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                px: 2,
                py: 1.5,
                '&:not(:last-child)': { borderBottom: '1px solid', borderColor: 'divider' },
              }}
            >
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, minWidth: 0 }}>
                <Typography
                  sx={{
                    fontSize: '13px',
                    fontWeight: 500,
                    color: 'text.primary',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {asset.name}
                </Typography>
                <Typography sx={{ fontSize: '11px', color: 'text.secondary', flexShrink: 0 }}>
                  {asset.contentType} &middot; {humanFileSize(asset.fileSize)}
                </Typography>
              </Box>
              <Box sx={{ display: 'flex', gap: 0.5, flexShrink: 0 }}>
                {asset.downloadUrl && (
                  <Tooltip title="Download">
                    <IconButton
                      size="small"
                      component="a"
                      href={asset.downloadUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <span style={{ fontSize: '14px' }}>{'\u2B07'}</span>
                    </IconButton>
                  </Tooltip>
                )}
                <Tooltip title="Promote to Project Assets">
                  <IconButton size="small" onClick={() => openExportDialog({ type: 'single', asset })}>
                    <span style={{ fontSize: '14px' }}>{'\u2B06'}</span>
                  </IconButton>
                </Tooltip>
              </Box>
            </Box>
          ))}
        </Paper>
      ))}

      <Dialog open={!!exportTarget} onClose={() => setExportTarget(null)} maxWidth="xs" fullWidth>
        <DialogTitle>
          {exportTarget?.type === 'all'
            ? 'Promote All Artifacts'
            : `Promote "${(exportTarget as { type: 'single'; asset: WorkflowRunAsset })?.asset?.name}"`}
        </DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            This will create project-level assets from workflow artifacts. You can optionally specify a folder to
            organize them.
          </Typography>
          <TextField
            fullWidth
            size="small"
            label="Folder (optional)"
            placeholder="Leave empty for root"
            value={folder}
            onChange={(e) => setFolder(e.target.value)}
            autoFocus
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setExportTarget(null)}>Cancel</Button>
          <Button variant="contained" onClick={handleConfirmExport} disabled={exporting}>
            {exporting ? 'Promoting...' : 'Promote'}
          </Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={!!snackbar}
        autoHideDuration={3000}
        onClose={() => setSnackbar(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert severity="info" onClose={() => setSnackbar(null)}>
          {snackbar}
        </Alert>
      </Snackbar>
    </Box>
  );
};
