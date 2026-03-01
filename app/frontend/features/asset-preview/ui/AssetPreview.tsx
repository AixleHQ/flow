import CloseIcon from '@mui/icons-material/Close';
import DownloadIcon from '@mui/icons-material/Download';
import { Box, Button, Chip, CircularProgress, IconButton, Tab, Tabs, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useEffect, useState } from 'react';
import Markdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

type PreviewType = 'markdown' | 'code' | 'image' | 'text' | 'binary';

export interface AssetPreviewData {
  name: string;
  contentType: string | null;
  fileSize: number | null;
  downloadUrl: string;
  createdAt: string;
}

interface AssetPreviewProps {
  asset: AssetPreviewData;
  onClose?: () => void;
}

function resolvePreviewType(name: string, contentType: string | null): PreviewType {
  const ext = name.split('.').pop()?.toLowerCase() ?? '';
  const mime = contentType?.toLowerCase() ?? '';

  if (mime.startsWith('image/') || ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'ico'].includes(ext)) {
    return 'image';
  }

  if (['md', 'markdown'].includes(ext) || mime === 'text/markdown') {
    return 'markdown';
  }

  const codeExts = [
    'ts',
    'tsx',
    'js',
    'jsx',
    'py',
    'rb',
    'go',
    'rs',
    'java',
    'c',
    'cpp',
    'h',
    'css',
    'scss',
    'html',
    'json',
    'yaml',
    'yml',
    'xml',
    'toml',
    'sh',
    'bash',
    'sql',
    'graphql',
    'proto',
    'dockerfile',
  ];
  if (
    codeExts.includes(ext) ||
    mime.includes('javascript') ||
    mime.includes('typescript') ||
    mime.includes('json') ||
    mime.includes('xml') ||
    mime.includes('yaml')
  ) {
    return 'code';
  }

  if (['txt', 'csv', 'log', 'env', 'gitignore', 'editorconfig'].includes(ext) || mime.startsWith('text/')) {
    return 'text';
  }

  return 'binary';
}

function formatSize(bytes: number | null): string {
  if (!bytes) return '—';
  if (bytes >= 1_073_741_824) return (bytes / 1_073_741_824).toFixed(2) + ' GB';
  if (bytes >= 1_048_576) return (bytes / 1_048_576).toFixed(2) + ' MB';
  if (bytes >= 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return bytes + ' B';
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
    gap: 2,
  },
  headerLeft: { flex: 1, minWidth: 0 },
  title: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  meta: {
    display: 'flex',
    gap: '12px',
    alignItems: 'center',
    fontSize: '12px',
    color: 'text.secondary',
  },
  headerActions: { display: 'flex', gap: '8px', alignItems: 'center' },
  content: { flex: 1, overflow: 'auto', padding: '20px' },
  codeBlock: {
    backgroundColor: 'background.elevated',
    borderRadius: '8px',
    padding: '16px',
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: '13px',
    lineHeight: 1.6,
    overflow: 'auto',
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
    color: 'text.primary',
  },
  markdownContent: {
    '& h1': { fontSize: '24px', fontWeight: 600, mb: '16px', color: 'text.primary' },
    '& h2': { fontSize: '20px', fontWeight: 600, mb: '12px', mt: '24px', color: 'text.primary' },
    '& h3': { fontSize: '16px', fontWeight: 600, mb: '8px', mt: '16px', color: 'text.primary' },
    '& p': { fontSize: '14px', lineHeight: 1.6, color: 'text.primary', mb: '12px' },
    '& code': {
      backgroundColor: 'background.elevated',
      padding: '2px 6px',
      borderRadius: '4px',
      fontSize: '13px',
      fontFamily: '"JetBrains Mono", monospace',
      color: 'primary.main',
    },
    '& pre': {
      backgroundColor: 'background.elevated',
      padding: '16px',
      borderRadius: '8px',
      overflow: 'auto',
      fontSize: '13px',
      fontFamily: '"JetBrains Mono", monospace',
      lineHeight: 1.6,
    },
    '& pre code': { backgroundColor: 'transparent', padding: 0 },
    '& ul, & ol': { marginLeft: '24px', mb: '12px' },
    '& li': { fontSize: '14px', lineHeight: 1.6, color: 'text.primary', mb: '4px' },
    '& blockquote': {
      borderLeft: '4px solid',
      borderColor: 'primary.main',
      paddingLeft: '16px',
      ml: 0,
      mb: '12px',
      fontStyle: 'italic',
      color: 'text.secondary',
    },
    '& table': { width: '100%', borderCollapse: 'collapse', mb: '16px' },
    '& th, & td': {
      border: '1px solid',
      borderColor: 'divider',
      padding: '8px 12px',
      textAlign: 'left',
      fontSize: '13px',
    },
    '& th': { backgroundColor: 'background.elevated', fontWeight: 600, color: 'text.primary' },
  },
  imageContainer: { display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '300px' },
  image: { maxWidth: '100%', maxHeight: '70vh', borderRadius: '8px' },
  centered: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2, py: 8 },
} satisfies Record<string, SxProps<Theme>>;

const AssetPreview = ({ asset, onClose }: AssetPreviewProps) => {
  const previewType = resolvePreviewType(asset.name, asset.contentType);
  const isTextual = previewType === 'markdown' || previewType === 'code' || previewType === 'text';

  const [viewMode, setViewMode] = useState<'preview' | 'raw'>('preview');
  const [content, setContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(isTextual);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isTextual) return;

    let cancelled = false;
    setLoading(true);
    setError(null);

    fetch(asset.downloadUrl)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.text();
      })
      .then((text) => {
        if (!cancelled) setContent(text);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [asset.downloadUrl, isTextual]);

  const renderContent = () => {
    if (loading) {
      return (
        <Box sx={styles.centered}>
          <CircularProgress size={28} />
          <Typography sx={{ color: 'text.secondary', fontSize: 13 }}>Loading content...</Typography>
        </Box>
      );
    }

    if (error) {
      return (
        <Box sx={styles.centered}>
          <Typography sx={{ color: 'error.main', fontSize: 14 }}>Failed to load: {error}</Typography>
        </Box>
      );
    }

    switch (previewType) {
      case 'markdown':
        if (viewMode === 'raw') {
          return (
            <Box sx={styles.codeBlock} component="pre">
              {content}
            </Box>
          );
        }
        return (
          <Box sx={styles.markdownContent}>
            <Markdown remarkPlugins={[remarkGfm]}>{content || ''}</Markdown>
          </Box>
        );

      case 'code':
      case 'text':
        return (
          <Box sx={styles.codeBlock} component="pre">
            {content}
          </Box>
        );

      case 'image':
        return (
          <Box sx={styles.imageContainer}>
            <Box component="img" src={asset.downloadUrl} alt={asset.name} sx={styles.image} />
          </Box>
        );

      case 'binary':
        return (
          <Box sx={styles.centered}>
            <Typography sx={{ fontSize: 48 }}>📦</Typography>
            <Typography sx={{ color: 'text.secondary', fontSize: 14 }}>
              Binary file — {formatSize(asset.fileSize)}
            </Typography>
            <Button variant="outlined" href={asset.downloadUrl} download={asset.name} sx={{ textTransform: 'none' }}>
              Download File
            </Button>
          </Box>
        );
    }
  };

  const ext = asset.name.split('.').pop()?.toLowerCase() ?? '';

  return (
    <Box sx={styles.container}>
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Typography sx={styles.title}>{asset.name}</Typography>
          <Box sx={styles.meta}>
            <Chip label={ext || previewType} size="small" sx={{ height: '20px', fontSize: '11px' }} />
            <Typography component="span">{formatSize(asset.fileSize)}</Typography>
            <Typography component="span">• {new Date(asset.createdAt).toLocaleString()}</Typography>
          </Box>
        </Box>
        <Box sx={styles.headerActions}>
          {previewType === 'markdown' && (
            <Tabs value={viewMode} onChange={(_, v) => setViewMode(v)} sx={{ minHeight: '40px' }}>
              <Tab label="Preview" value="preview" sx={{ minHeight: '40px', textTransform: 'none', py: 0 }} />
              <Tab label="Raw" value="raw" sx={{ minHeight: '40px', textTransform: 'none', py: 0 }} />
            </Tabs>
          )}
          <Tooltip title="Download">
            <IconButton size="small" component="a" href={asset.downloadUrl} download={asset.name}>
              <DownloadIcon fontSize="small" />
            </IconButton>
          </Tooltip>
          {onClose && (
            <IconButton size="small" onClick={onClose}>
              <CloseIcon fontSize="small" />
            </IconButton>
          )}
        </Box>
      </Box>
      <Box sx={styles.content}>{renderContent()}</Box>
    </Box>
  );
};

export default AssetPreview;
