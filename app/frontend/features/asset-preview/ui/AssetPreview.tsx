import { Box, Button, Chip, IconButton, Tab, Tabs, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface IAsset {
  id: string;
  name: string;
  type: 'markdown' | 'code' | 'json' | 'text' | 'image' | 'binary';
  mimeType?: string;
  size: number;
  content?: string;
  url?: string;
  createdAt: string;
  stepId?: string;
  stepName?: string;
}

interface AssetPreviewProps {
  asset: IAsset;
  onClose?: () => void;
}

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    backgroundColor: 'background.default',
  },
  header: {
    padding: '16px 20px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  headerLeft: {
    flex: 1,
  },
  title: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
  },
  meta: {
    display: 'flex',
    gap: '12px',
    alignItems: 'center',
    fontSize: '12px',
    color: 'text.secondary',
  },
  headerActions: {
    display: 'flex',
    gap: '8px',
  },
  tabs: {
    borderBottom: '1px solid',
    borderColor: 'divider',
    minHeight: '48px',
  },
  content: {
    flex: 1,
    overflow: 'auto',
    padding: '20px',
  },
  codeBlock: {
    backgroundColor: 'background.elevated',
    borderRadius: '8px',
    padding: '16px',
    fontFamily: 'monospace',
    fontSize: '13px',
    lineHeight: 1.6,
    overflow: 'auto',
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
  },
  markdownContent: {
    '& h1': {
      fontSize: '24px',
      fontWeight: 600,
      marginBottom: '16px',
      color: 'text.primary',
    },
    '& h2': {
      fontSize: '20px',
      fontWeight: 600,
      marginBottom: '12px',
      marginTop: '24px',
      color: 'text.primary',
    },
    '& h3': {
      fontSize: '16px',
      fontWeight: 600,
      marginBottom: '8px',
      marginTop: '16px',
      color: 'text.primary',
    },
    '& p': {
      fontSize: '14px',
      lineHeight: 1.6,
      color: 'text.primary',
      marginBottom: '12px',
    },
    '& code': {
      backgroundColor: 'background.elevated',
      padding: '2px 6px',
      borderRadius: '4px',
      fontSize: '13px',
      fontFamily: 'monospace',
      color: 'primary.main',
    },
    '& pre': {
      backgroundColor: 'background.elevated',
      padding: '16px',
      borderRadius: '8px',
      overflow: 'auto',
      fontSize: '13px',
      fontFamily: 'monospace',
      lineHeight: 1.6,
    },
    '& pre code': {
      backgroundColor: 'transparent',
      padding: 0,
    },
    '& ul, & ol': {
      marginLeft: '24px',
      marginBottom: '12px',
    },
    '& li': {
      fontSize: '14px',
      lineHeight: 1.6,
      color: 'text.primary',
      marginBottom: '4px',
    },
    '& blockquote': {
      borderLeft: '4px solid',
      borderColor: 'primary.main',
      paddingLeft: '16px',
      marginLeft: 0,
      marginBottom: '12px',
      fontStyle: 'italic',
      color: 'text.secondary',
    },
    '& table': {
      width: '100%',
      borderCollapse: 'collapse',
      marginBottom: '16px',
    },
    '& th, & td': {
      border: '1px solid',
      borderColor: 'divider',
      padding: '8px 12px',
      textAlign: 'left',
      fontSize: '13px',
    },
    '& th': {
      backgroundColor: 'background.elevated',
      fontWeight: 600,
      color: 'text.primary',
    },
  },
  imageContainer: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    minHeight: '400px',
  },
  image: {
    maxWidth: '100%',
    maxHeight: '80vh',
    borderRadius: '8px',
  },
  binaryContainer: {
    textAlign: 'center',
    padding: '64px 32px',
  },
  binaryIcon: {
    fontSize: '64px',
    marginBottom: '16px',
  },
  downloadButton: {
    textTransform: 'none',
    marginTop: '16px',
  },
  emptyState: {
    textAlign: 'center',
    padding: '64px 32px',
  },
  emptyIcon: {
    fontSize: '48px',
    marginBottom: '16px',
  },
  emptyText: {
    fontSize: '14px',
    color: 'text.secondary',
  },
} satisfies Record<string, SxProps<Theme>>;

const formatSize = (size: number): string => {
  if (size >= 1_073_741_824) return (size / 1_073_741_824).toFixed(2) + ' GB';
  if (size >= 1_048_576) return (size / 1_048_576).toFixed(2) + ' MB';
  if (size >= 1024) return (size / 1024).toFixed(2) + ' KB';
  return size + ' B';
};

const AssetPreview = ({ asset, onClose }: AssetPreviewProps) => {
  const [viewMode, setViewMode] = useState<'preview' | 'raw'>('preview');

  const renderContent = () => {
    if (!asset.content && !asset.url) {
      return (
        <Box sx={styles.emptyState}>
          <Typography sx={styles.emptyIcon}>📄</Typography>
          <Typography sx={styles.emptyText}>No content available</Typography>
        </Box>
      );
    }

    switch (asset.type) {
      case 'markdown':
        if (viewMode === 'raw') {
          return (
            <Box sx={styles.codeBlock} component="pre">
              {asset.content}
            </Box>
          );
        }
        return (
          <Box sx={styles.markdownContent}>
            <Markdown remarkPlugins={[remarkGfm]}>{asset.content || ''}</Markdown>
          </Box>
        );

      case 'code':
      case 'json':
      case 'text':
        return (
          <Box sx={styles.codeBlock} component="pre">
            {asset.content}
          </Box>
        );

      case 'image':
        return (
          <Box sx={styles.imageContainer}>
            <Box component="img" src={asset.url} alt={asset.name} sx={styles.image} />
          </Box>
        );

      case 'binary':
        return (
          <Box sx={styles.binaryContainer}>
            <Typography sx={styles.binaryIcon}>📦</Typography>
            <Typography sx={{ fontSize: '14px', color: 'text.secondary', marginBottom: '8px' }}>
              Binary file: {formatSize(asset.size)}
            </Typography>
            {asset.url && (
              <Button variant="outlined" href={asset.url} download={asset.name} sx={styles.downloadButton}>
                Download File
              </Button>
            )}
          </Box>
        );

      default:
        return (
          <Box sx={styles.emptyState}>
            <Typography sx={styles.emptyIcon}>❓</Typography>
            <Typography sx={styles.emptyText}>Unsupported asset type</Typography>
          </Box>
        );
    }
  };

  return (
    <Box sx={styles.container}>
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Typography sx={styles.title}>{asset.name}</Typography>
          <Box sx={styles.meta}>
            <Chip label={asset.type} size="small" sx={{ height: '20px', fontSize: '11px' }} />
            <Typography>{formatSize(asset.size)}</Typography>
            {asset.stepName && <Typography>• {asset.stepName}</Typography>}
            <Typography>• {new Date(asset.createdAt).toLocaleString()}</Typography>
          </Box>
        </Box>
        <Box sx={styles.headerActions}>
          {(asset.type === 'markdown' || asset.type === 'code' || asset.type === 'json') && (
            <Tabs value={viewMode} onChange={(_, v) => setViewMode(v)} sx={styles.tabs}>
              <Tab label="Preview" value="preview" sx={{ minHeight: '48px', textTransform: 'none' }} />
              <Tab label="Raw" value="raw" sx={{ minHeight: '48px', textTransform: 'none' }} />
            </Tabs>
          )}
          {onClose && (
            <IconButton size="small" onClick={onClose}>
              ✕
            </IconButton>
          )}
        </Box>
      </Box>

      <Box sx={styles.content}>{renderContent()}</Box>
    </Box>
  );
};

export default AssetPreview;
