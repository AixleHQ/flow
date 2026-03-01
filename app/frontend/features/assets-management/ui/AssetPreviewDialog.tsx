import { Dialog, DialogContent } from '@mui/material';
import { useMemo, type FC, type ReactNode } from 'react';

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

function toSameOriginPath(url: string): string {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
}

export const AssetPreviewDialog: FC<AssetPreviewDialogProps> = ({ open, onClose, asset, renderPreview }) => {
  const previewData = useMemo<AssetPreviewData | null>(() => {
    if (!asset?.latestVersion?.fileUrl) return null;

    return {
      name: asset.name,
      contentType: asset.latestVersion.contentType,
      fileSize: asset.latestVersion.fileSize,
      downloadUrl: toSameOriginPath(asset.latestVersion.fileUrl),
      createdAt: asset.createdAt,
    };
  }, [asset]);

  if (!previewData) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="lg" fullWidth PaperProps={{ sx: { height: '80vh' } }}>
      <DialogContent sx={{ p: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        {renderPreview(previewData, onClose)}
      </DialogContent>
    </Dialog>
  );
};
