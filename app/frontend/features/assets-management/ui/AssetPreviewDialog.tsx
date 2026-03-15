import { Dialog, DialogContent } from '@mui/material';
import { useMemo, type FC, type ReactNode } from 'react';

import Routes from 'shared/routes';

import type { Asset } from '../lib/types';

export interface AssetPreviewData {
  name: string;
  contentType: string | null;
  fileSize: number | null;
  downloadUrl: string;
  createdAt: string;
}

interface AssetPreviewDialogProps {
  open: boolean;
  onClose: () => void;
  asset: Asset | null;
  projectId?: number;
  renderPreview: (data: AssetPreviewData, onClose: () => void) => ReactNode;
}

export const AssetPreviewDialog: FC<AssetPreviewDialogProps> = ({ open, onClose, asset, projectId, renderPreview }) => {
  const { downloadApiV1CompanyProjectAssetPath, downloadApiV1CompanyAssetPath } = Routes.backend;
  const previewData = useMemo<AssetPreviewData | null>(() => {
    if (!asset?.latestVersion?.fileUrl) return null;

    const basePath = projectId
      ? downloadApiV1CompanyProjectAssetPath(projectId, asset.id)
      : downloadApiV1CompanyAssetPath(asset.id);
    const downloadUrl = `${basePath}?inline=true`;

    return {
      name: asset.name,
      contentType: asset.latestVersion.contentType,
      fileSize: asset.latestVersion.fileSize,
      downloadUrl,
      createdAt: asset.createdAt,
    };
  }, [asset, projectId]);

  if (!previewData) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="lg" fullWidth PaperProps={{ sx: { height: '80vh' } }}>
      <DialogContent sx={{ p: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {renderPreview(previewData, onClose)}
      </DialogContent>
    </Dialog>
  );
};
