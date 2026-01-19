import { Box, Typography, CircularProgress, IconButton, Tooltip } from '@mui/material';
import { useState, useEffect, useMemo, useCallback } from 'react';
import CodeMirror from '@uiw/react-codemirror';
import { vscodeDark } from '@uiw/codemirror-theme-vscode';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';
import { json } from '@codemirror/lang-json';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { markdown } from '@codemirror/lang-markdown';
import { sql } from '@codemirror/lang-sql';
import { xml } from '@codemirror/lang-xml';
import { yaml } from '@codemirror/lang-yaml';
import { EditorView } from '@codemirror/view';
import { Document, Page, pdfjs } from 'react-pdf';
import 'react-pdf/dist/Page/AnnotationLayer.css';
import 'react-pdf/dist/Page/TextLayer.css';

// Set up PDF.js worker
pdfjs.GlobalWorkerOptions.workerSrc = `//unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

// Icons
const CloseIcon = () => <span style={{ fontSize: '16px' }}>✕</span>;
const RefreshIcon = () => <span style={{ fontSize: '14px' }}>↻</span>;

interface IFileViewerProps {
  watcherPort: number | null;
  filePath: string | null;
  onClose: () => void;
}

interface IFileContent {
  path: string;
  name: string;
  extension: string;
  size: number;
  content: string;
  encoding?: 'text' | 'base64';
  fileType?: 'text' | 'image' | 'pdf' | 'video' | 'audio' | 'binary';
  mimeType?: string;
  mtime: string;
}

interface IFileError {
  error: string;
  message?: string;
  size?: number;
  maxSize?: number;
}

// Get CodeMirror language extension based on file extension
const getLanguageExtension = (ext: string) => {
  switch (ext) {
    case 'js':
    case 'jsx':
      return javascript({ jsx: true });
    case 'ts':
    case 'tsx':
      return javascript({ jsx: true, typescript: true });
    case 'py':
      return python();
    case 'json':
      return json();
    case 'html':
    case 'htm':
      return html();
    case 'css':
    case 'scss':
    case 'less':
      return css();
    case 'md':
    case 'markdown':
      return markdown();
    case 'sql':
      return sql();
    case 'xml':
      return xml();
    case 'yml':
    case 'yaml':
      return yaml();
    default:
      return [];
  }
};

// Get display language/type name
const getTypeName = (fileContent: IFileContent): string => {
  const { extension, fileType, mimeType } = fileContent;

  if (fileType === 'image') {
    const imageNames: Record<string, string> = {
      png: 'PNG Image',
      jpg: 'JPEG Image',
      jpeg: 'JPEG Image',
      gif: 'GIF Image',
      webp: 'WebP Image',
      svg: 'SVG Image',
      ico: 'Icon',
      bmp: 'Bitmap Image',
    };
    return imageNames[extension] || 'Image';
  }

  if (fileType === 'pdf') return 'PDF Document';
  if (fileType === 'video') return 'Video';
  if (fileType === 'audio') return 'Audio';
  if (fileType === 'binary') return mimeType || 'Binary File';

  // Text/code files
  const langMap: Record<string, string> = {
    ts: 'TypeScript',
    tsx: 'TypeScript JSX',
    js: 'JavaScript',
    jsx: 'JavaScript JSX',
    json: 'JSON',
    md: 'Markdown',
    rb: 'Ruby',
    py: 'Python',
    yml: 'YAML',
    yaml: 'YAML',
    sh: 'Shell',
    bash: 'Bash',
    css: 'CSS',
    scss: 'SCSS',
    less: 'LESS',
    html: 'HTML',
    htm: 'HTML',
    xml: 'XML',
    svg: 'SVG',
    sql: 'SQL',
    txt: 'Plain Text',
    log: 'Log',
    env: 'Environment',
    gitignore: 'Git Ignore',
    dockerfile: 'Dockerfile',
    makefile: 'Makefile',
  };
  return langMap[extension.toLowerCase()] || extension.toUpperCase() || 'Plain Text';
};

const styles = {
  container: {
    height: '100%',
    width: '100%',
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: '#1e1e1e',
    color: '#cccccc',
    overflow: 'hidden',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '8px 12px',
    borderBottom: '1px solid #3d3d3d',
    backgroundColor: '#252526',
    flexShrink: 0,
  },
  headerLeft: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    overflow: 'hidden',
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '4px',
    flexShrink: 0,
  },
  fileName: {
    color: '#e0e0e0',
    fontSize: '13px',
    fontWeight: 500,
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  filePath: {
    color: '#808080',
    fontSize: '11px',
    whiteSpace: 'nowrap',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
  },
  editorContainer: {
    flex: 1,
    overflow: 'hidden',
    '& .cm-editor': {
      height: '100%',
    },
    '& .cm-scroller': {
      fontFamily: 'JetBrains Mono, Menlo, Monaco, Consolas, monospace !important',
      fontSize: '13px !important',
    },
  },
  mediaContainer: {
    flex: 1,
    overflow: 'auto',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '16px',
    backgroundColor: '#1a1a1a',
  },
  image: {
    maxWidth: '100%',
    maxHeight: '100%',
    objectFit: 'contain' as const,
    borderRadius: '4px',
    boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
  },
  pdfContainer: {
    flex: 1,
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
  },
  pdfControls: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '12px',
    padding: '8px',
    borderBottom: '1px solid #3d3d3d',
    backgroundColor: '#252526',
  },
  pdfNavButton: {
    color: '#808080',
    '&:hover': {
      color: '#cccccc',
      backgroundColor: 'rgba(255,255,255,0.1)',
    },
    '&:disabled': {
      color: '#404040',
    },
  },
  pdfPageInfo: {
    color: '#cccccc',
    fontSize: '13px',
    minWidth: '120px',
    textAlign: 'center',
  },
  pdfScrollContainer: {
    flex: 1,
    overflow: 'auto',
    display: 'flex',
    justifyContent: 'center',
    padding: '16px',
    backgroundColor: '#1a1a1a',
    '& .react-pdf__Document': {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
    },
    '& .react-pdf__Page': {
      boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
      marginBottom: '16px',
    },
    '& .react-pdf__Page canvas': {
      maxWidth: '100%',
      height: 'auto !important',
    },
  },
  unsupportedContainer: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '12px',
    color: '#808080',
    padding: '24px',
    textAlign: 'center',
  },
  unsupportedIcon: {
    fontSize: '48px',
    opacity: 0.5,
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flex: 1,
  },
  error: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    flex: 1,
    color: '#f44747',
    fontSize: '13px',
    padding: '16px',
    textAlign: 'center',
    gap: '8px',
  },
  errorIcon: {
    fontSize: '32px',
  },
  errorMessage: {
    color: '#808080',
    fontSize: '12px',
  },
  empty: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flex: 1,
    color: '#808080',
    fontSize: '13px',
  },
  meta: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '6px 12px',
    borderTop: '1px solid #3d3d3d',
    backgroundColor: '#252526',
    fontSize: '11px',
    color: '#808080',
    flexShrink: 0,
  },
  iconButton: {
    color: '#808080',
    padding: '4px',
    '&:hover': {
      color: '#cccccc',
      backgroundColor: 'rgba(255,255,255,0.1)',
    },
  },
} as const;

// Helper to format file size
const formatFileSize = (bytes: number): string => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

// Image viewer component
const ImageViewer = ({ content, mimeType, name }: { content: string; mimeType: string; name: string }) => {
  const dataUrl = `data:${mimeType};base64,${content}`;
  return (
    <Box sx={styles.mediaContainer}>
      <img src={dataUrl} alt={name} style={styles.image} />
    </Box>
  );
};

// PDF viewer component
const PdfViewer = ({ content }: { content: string; mimeType: string }) => {
  const [numPages, setNumPages] = useState<number | null>(null);
  const [currentPage, setCurrentPage] = useState(1);

  const onDocumentLoadSuccess = useCallback(({ numPages }: { numPages: number }) => {
    setNumPages(numPages);
  }, []);

  // Convert base64 to data URL for react-pdf
  const pdfData = useMemo(() => {
    return `data:application/pdf;base64,${content}`;
  }, [content]);

  return (
    <Box sx={styles.pdfContainer}>
      <Box sx={styles.pdfControls}>
        <IconButton
          onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
          disabled={currentPage <= 1}
          sx={styles.pdfNavButton}
          size="small"
        >
          ◀
        </IconButton>
        <Typography sx={styles.pdfPageInfo}>
          Page {currentPage} of {numPages || '?'}
        </Typography>
        <IconButton
          onClick={() => setCurrentPage((p) => Math.min(numPages || p, p + 1))}
          disabled={currentPage >= (numPages || 1)}
          sx={styles.pdfNavButton}
          size="small"
        >
          ▶
        </IconButton>
      </Box>
      <Box sx={styles.pdfScrollContainer}>
        <Document file={pdfData} onLoadSuccess={onDocumentLoadSuccess} loading={<CircularProgress size={24} sx={{ color: '#4ec9b0' }} />}>
          <Page pageNumber={currentPage} renderTextLayer={true} renderAnnotationLayer={true} />
        </Document>
      </Box>
    </Box>
  );
};

// Unsupported file type component
const UnsupportedViewer = ({ fileType, mimeType }: { fileType: string; mimeType?: string }) => {
  const icons: Record<string, string> = {
    video: '🎬',
    audio: '🎵',
    binary: '📦',
  };

  return (
    <Box sx={styles.unsupportedContainer}>
      <span style={styles.unsupportedIcon}>{icons[fileType] || '📄'}</span>
      <Typography sx={{ fontSize: '14px', color: '#cccccc' }}>Preview not available</Typography>
      <Typography sx={{ fontSize: '12px', color: '#808080' }}>
        {fileType === 'video' && 'Video files cannot be previewed in this viewer'}
        {fileType === 'audio' && 'Audio files cannot be previewed in this viewer'}
        {fileType === 'binary' && `Binary file${mimeType ? ` (${mimeType})` : ''}`}
      </Typography>
    </Box>
  );
};

// Code viewer component
const CodeViewer = ({ content, extension }: { content: string; extension: string }) => {
  const extensions = useMemo(() => {
    const langExt = getLanguageExtension(extension);
    return [EditorView.editable.of(false), EditorView.lineWrapping, ...(Array.isArray(langExt) ? langExt : [langExt])];
  }, [extension]);

  return (
    <Box sx={styles.editorContainer}>
      <CodeMirror
        value={content}
        height="100%"
        theme={vscodeDark}
        extensions={extensions}
        basicSetup={{
          lineNumbers: true,
          highlightActiveLineGutter: false,
          highlightActiveLine: false,
          foldGutter: true,
          dropCursor: false,
          allowMultipleSelections: false,
          indentOnInput: false,
          bracketMatching: true,
          closeBrackets: false,
          autocompletion: false,
          rectangularSelection: false,
          crosshairCursor: false,
          highlightSelectionMatches: true,
          closeBracketsKeymap: false,
          searchKeymap: true,
          foldKeymap: true,
          completionKeymap: false,
          lintKeymap: false,
        }}
      />
    </Box>
  );
};

export const FileViewer = ({ watcherPort, filePath, onClose }: IFileViewerProps) => {
  const [fileContent, setFileContent] = useState<IFileContent | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [errorDetails, setErrorDetails] = useState<string | null>(null);

  const fetchFileContent = async () => {
    if (!watcherPort || !filePath) return;

    setLoading(true);
    setError(null);
    setErrorDetails(null);

    try {
      const response = await fetch(`http://localhost:${watcherPort}/file?path=${encodeURIComponent(filePath)}`);
      const data = await response.json();

      if (!response.ok) {
        const errorData = data as IFileError;
        setError(errorData.error || 'Failed to load file');
        if (errorData.message) {
          setErrorDetails(errorData.message);
        } else if (errorData.size && errorData.maxSize) {
          setErrorDetails(`File size: ${formatFileSize(errorData.size)}, Max allowed: ${formatFileSize(errorData.maxSize)}`);
        }
        return;
      }

      setFileContent(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load file');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchFileContent();
  }, [watcherPort, filePath]);

  if (!filePath) {
    return (
      <Box sx={styles.container}>
        <Box sx={styles.empty}>Select a file to view its contents</Box>
      </Box>
    );
  }

  if (loading) {
    return (
      <Box sx={styles.container}>
        <Box sx={styles.header}>
          <Box sx={styles.headerLeft}>
            <Typography sx={styles.fileName}>Loading...</Typography>
          </Box>
          <Box sx={styles.headerRight}>
            <Tooltip title="Close">
              <IconButton onClick={onClose} sx={styles.iconButton} size="small">
                <CloseIcon />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
        <Box sx={styles.loading}>
          <CircularProgress size={24} sx={{ color: '#4ec9b0' }} />
        </Box>
      </Box>
    );
  }

  if (error) {
    return (
      <Box sx={styles.container}>
        <Box sx={styles.header}>
          <Box sx={styles.headerLeft}>
            <Typography sx={styles.fileName}>{filePath.split('/').pop()}</Typography>
          </Box>
          <Box sx={styles.headerRight}>
            <Tooltip title="Retry">
              <IconButton onClick={fetchFileContent} sx={styles.iconButton} size="small">
                <RefreshIcon />
              </IconButton>
            </Tooltip>
            <Tooltip title="Close">
              <IconButton onClick={onClose} sx={styles.iconButton} size="small">
                <CloseIcon />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
        <Box sx={styles.error}>
          <span style={styles.errorIcon}>⚠️</span>
          <span>{error}</span>
          {errorDetails && <span style={styles.errorMessage}>{errorDetails}</span>}
        </Box>
      </Box>
    );
  }

  if (!fileContent) {
    return null;
  }

  const typeName = getTypeName(fileContent);
  const fileType = fileContent.fileType || 'text';

  // Render content based on file type
  const renderContent = () => {
    switch (fileType) {
      case 'image':
        return <ImageViewer content={fileContent.content} mimeType={fileContent.mimeType || 'image/png'} name={fileContent.name} />;
      case 'pdf':
        return <PdfViewer content={fileContent.content} mimeType={fileContent.mimeType || 'application/pdf'} />;
      case 'video':
      case 'audio':
      case 'binary':
        return <UnsupportedViewer fileType={fileType} mimeType={fileContent.mimeType} />;
      default:
        return <CodeViewer content={fileContent.content} extension={fileContent.extension} />;
    }
  };

  // Calculate line count only for text files
  const lineCount = fileType === 'text' ? fileContent.content.split('\n').length : null;

  return (
    <Box sx={styles.container}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Typography sx={styles.fileName}>{fileContent.name}</Typography>
          <Typography sx={styles.filePath}>{fileContent.path}</Typography>
        </Box>
        <Box sx={styles.headerRight}>
          <Tooltip title="Refresh">
            <IconButton onClick={fetchFileContent} sx={styles.iconButton} size="small">
              <RefreshIcon />
            </IconButton>
          </Tooltip>
          <Tooltip title="Close">
            <IconButton onClick={onClose} sx={styles.iconButton} size="small">
              <CloseIcon />
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      {/* Content */}
      {renderContent()}

      {/* Footer with meta info */}
      <Box sx={styles.meta}>
        <span>{typeName}</span>
        {lineCount && (
          <>
            <span>•</span>
            <span>{lineCount} lines</span>
          </>
        )}
        <span>•</span>
        <span>{formatFileSize(fileContent.size)}</span>
      </Box>
    </Box>
  );
};
