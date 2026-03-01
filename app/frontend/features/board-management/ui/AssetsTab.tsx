import CloudUploadIcon from '@mui/icons-material/CloudUpload';
import DeleteIcon from '@mui/icons-material/Delete';
import DownloadIcon from '@mui/icons-material/Download';
import { Box, Button, Chip, IconButton, List, ListItem, ListItemText, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useCallback, useRef } from 'react';

import type { TaskAsset } from 'entities/board-task';

import { useCreateAssetMutation, useDeleteAssetMutation, useGetTaskAssetsQuery } from '../api/boardApi';

interface AssetsTabProps {
  taskId: number;
  projectId: number;
}

const styles = {
  upload: { display: 'flex', justifyContent: 'flex-end', mb: 2 },
  listItem: { borderBottom: '1px solid', borderColor: 'divider', px: 0 },
  meta: { fontSize: '11px', color: 'text.secondary' },
  tags: { display: 'flex', gap: 0.5, mt: 0.5 },
  tagChip: { height: 18, fontSize: '10px' },
} satisfies Record<string, SxProps<Theme>>;

function formatFileSize(bytes: number | null): string {
  if (!bytes) return 'Unknown size';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export const AssetsTab = ({ taskId, projectId }: AssetsTabProps) => {
  const { data: assets = [] } = useGetTaskAssetsQuery({ projectId, taskId });
  const [createAsset] = useCreateAssetMutation();
  const [deleteAsset] = useDeleteAssetMutation();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleUpload = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      const formData = new FormData();
      formData.append('task_asset[name]', file.name);
      formData.append('task_asset[file]', file);
      await createAsset({ projectId, taskId, formData });
      if (fileInputRef.current) fileInputRef.current.value = '';
    },
    [createAsset, projectId, taskId],
  );

  return (
    <Box>
      <Box sx={styles.upload}>
        <input ref={fileInputRef} type="file" hidden onChange={handleUpload} />
        <Button
          variant="outlined"
          size="small"
          startIcon={<CloudUploadIcon />}
          onClick={() => fileInputRef.current?.click()}
        >
          Upload File
        </Button>
      </Box>

      {assets.length === 0 ? (
        <Typography sx={{ color: 'text.disabled', fontSize: '13px', textAlign: 'center', py: 3 }}>
          No assets yet
        </Typography>
      ) : (
        <List disablePadding>
          {assets.map((asset: TaskAsset) => (
            <ListItem
              key={asset.id}
              sx={styles.listItem}
              secondaryAction={
                <Box sx={{ display: 'flex', gap: 0.5 }}>
                  {asset.fileUrl && (
                    <IconButton size="small" component="a" href={asset.fileUrl} target="_blank">
                      <DownloadIcon fontSize="small" />
                    </IconButton>
                  )}
                  <IconButton size="small" onClick={() => deleteAsset({ projectId, taskId, assetId: asset.id })}>
                    <DeleteIcon fontSize="small" />
                  </IconButton>
                </Box>
              }
            >
              <ListItemText
                primary={asset.name}
                secondary={
                  <Box>
                    <Typography sx={styles.meta}>
                      {formatFileSize(asset.fileSize)} · {asset.contentType || 'Unknown type'} · {asset.authorType}
                    </Typography>
                    {asset.tags.length > 0 && (
                      <Box sx={styles.tags}>
                        {asset.tags.map((tag) => (
                          <Chip key={tag} label={tag} size="small" variant="outlined" sx={styles.tagChip} />
                        ))}
                      </Box>
                    )}
                  </Box>
                }
              />
            </ListItem>
          ))}
        </List>
      )}
    </Box>
  );
};
