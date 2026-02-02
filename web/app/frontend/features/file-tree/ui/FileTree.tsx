import { Box, Typography, CircularProgress } from '@mui/material';
import cx from 'classnames';
import { useState, useEffect, useCallback, useMemo } from 'react';
import TreeView, { flattenTree, INode, ITreeViewOnNodeSelectProps } from 'react-accessible-treeview';
import { FileIcon, defaultStyles, DefaultExtensionType } from 'react-file-icon';

import './FileTree.css';

// Folder icons
const FolderIcon = () => (
  <span className="tree-node__icon tree-node__icon--folder">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path
        d="M1.5 3.5h5l1 1h6a1 1 0 011 1v7a1 1 0 01-1 1h-11a1 1 0 01-1-1v-8a1 1 0 011-1z"
        fill="#dcb67a"
        stroke="#c4a35a"
        strokeWidth="0.5"
      />
    </svg>
  </span>
);

const FolderOpenIcon = () => (
  <span className="tree-node__icon tree-node__icon--folder">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M1.5 3.5h5l1 1h6a1 1 0 011 1v1h-12v-2a1 1 0 011-1z" fill="#dcb67a" stroke="#c4a35a" strokeWidth="0.5" />
      <path d="M0.5 6.5h13l-2 7h-10l-1-7z" fill="#e8c77b" stroke="#c4a35a" strokeWidth="0.5" />
    </svg>
  </span>
);

// File icon using react-file-icon
const FileIconComponent = ({ name }: { name: string }) => {
  const ext = (name.split('.').pop()?.toLowerCase() || '') as DefaultExtensionType;

  // Get default styles for the extension, or use a generic style
  const iconStyles = defaultStyles[ext] || {};

  return (
    <span className="tree-node__icon tree-node__icon--file">
      <FileIcon extension={ext} {...iconStyles} />
    </span>
  );
};

interface IWatcherTreeNode {
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: IWatcherTreeNode[];
  size?: number;
  extension?: string;
}

interface IFileTreeProps {
  /** Watcher URL (e.g., http://localhost/t/{token}/fs) - preferred */
  watcherUrl?: string | null;
  /** @deprecated Use watcherUrl instead. Direct port for legacy support */
  watcherPort?: number | null;
  onFileSelect?: (path: string) => void;
  selectedPath?: string | null;
  hideHeader?: boolean;
}

interface ITreeNode {
  name: string;
  id: string;
  children?: ITreeNode[];
  metadata?: {
    type: 'file' | 'directory';
    path: string;
    size?: number;
  };
}

// Collect all directory IDs for auto-expand
const collectDirectoryIds = (nodes: IWatcherTreeNode[]): string[] => {
  const ids: string[] = [];
  for (const node of nodes) {
    if (node.type === 'directory') {
      ids.push(node.path || node.name);
      if (node.children) {
        ids.push(...collectDirectoryIds(node.children));
      }
    }
  }
  return ids;
};

// Convert watcher tree format to react-accessible-treeview format
const convertToTreeViewFormat = (nodes: IWatcherTreeNode[]): ITreeNode[] => {
  return nodes.map((node) => {
    const id = node.path || node.name;
    const result: ITreeNode = {
      name: node.name,
      id,
      metadata: {
        type: node.type,
        path: node.path,
        size: node.size,
      },
    };

    // For directories, always set children array (even if empty)
    // This is required for react-accessible-treeview to treat them as expandable branches
    if (node.type === 'directory') {
      result.children = node.children ? convertToTreeViewFormat(node.children) : [];
    }

    return result;
  });
};

const styles = {
  container: {
    height: '100%',
    width: '100%',
    overflow: 'auto',
    backgroundColor: '#1e1e1e',
    color: '#cccccc',
    fontFamily: 'JetBrains Mono, Menlo, Monaco, monospace',
    fontSize: '13px',
  },
  header: {
    padding: '12px 16px',
    borderBottom: '1px solid #3d3d3d',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  title: {
    color: '#808080',
    fontSize: '11px',
    fontWeight: 600,
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  treeContainer: {
    padding: '8px 0',
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100px',
  },
  error: {
    padding: '16px',
    color: '#f44747',
    fontSize: '12px',
  },
  empty: {
    padding: '16px',
    color: '#808080',
    fontSize: '12px',
    textAlign: 'center',
  },
} as const;

export const FileTree = ({
  watcherUrl,
  watcherPort,
  onFileSelect,
  selectedPath,
  hideHeader = false,
}: IFileTreeProps) => {
  const [treeData, setTreeData] = useState<IWatcherTreeNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());

  // Compute base URL: prefer watcherUrl, fallback to port-based URL
  const baseUrl = watcherUrl || (watcherPort ? `http://localhost:${watcherPort}` : null);
  // WebSocket URL: convert http to ws
  const wsUrl = baseUrl?.replace(/^http/, 'ws') || null;

  // Fetch initial tree
  const fetchTree = useCallback(async () => {
    if (!baseUrl) return;

    try {
      setLoading(true);
      setError(null);
      const response = await fetch(`${baseUrl}/tree`, { credentials: 'include' });
      if (!response.ok) throw new Error('Failed to fetch tree');
      const data = await response.json();
      // API returns { root, tree, timestamp } - extract tree array
      const tree = Array.isArray(data) ? data : data.tree || [];
      setTreeData(tree);

      // Auto-expand all directories
      const dirIds = collectDirectoryIds(tree);
      setExpandedIds((prev) => {
        const next = new Set(prev);
        dirIds.forEach((id) => next.add(id));
        return next;
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load file tree');
    } finally {
      setLoading(false);
    }
  }, [baseUrl]);

  // WebSocket for real-time updates
  useEffect(() => {
    if (!wsUrl) return;

    fetchTree();

    let ws: WebSocket | null = null;
    let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;
    let isMounted = true;

    const connect = () => {
      if (!isMounted) return;

      ws = new WebSocket(wsUrl);

      ws.onopen = () => {
        if (isMounted) {
          setError(null); // Clear any previous errors
        }
      };

      ws.onmessage = (event) => {
        if (!isMounted) return;
        try {
          const message = JSON.parse(event.data);
          if (message.type === 'change') {
            // Refetch tree on any change
            fetchTree();
          } else if (message.type === 'tree') {
            // Handle tree data - could be array or { tree: [...] }
            const tree = Array.isArray(message.data) ? message.data : message.data?.tree || [];
            setTreeData(tree);
            // Auto-expand new directories
            const dirIds = collectDirectoryIds(tree);
            setExpandedIds((prev) => {
              const next = new Set(prev);
              dirIds.forEach((id) => next.add(id));
              return next;
            });
            setLoading(false);
          } else if (message.type === 'ready') {
            setLoading(false);
          }
        } catch {
          // Ignore parse errors
        }
      };

      ws.onerror = () => {
        // Don't set error immediately - wait for close to determine if we should reconnect
      };

      ws.onclose = () => {
        if (isMounted) {
          // Try to reconnect after a delay
          reconnectTimeout = setTimeout(connect, 2000);
        }
      };
    };

    connect();

    return () => {
      isMounted = false;
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout);
      }
      if (ws) {
        ws.close();
      }
    };
  }, [wsUrl, fetchTree]);

  // Convert to flattened format for react-accessible-treeview
  const flattenedData = useMemo(() => {
    if (treeData.length === 0) {
      return flattenTree({ name: '', children: [] });
    }

    const rootNode: ITreeNode = {
      name: '',
      id: 'root',
      children: convertToTreeViewFormat(treeData),
    };

    return flattenTree(rootNode);
  }, [treeData]);

  const handleNodeSelect = useCallback(
    (props: ITreeViewOnNodeSelectProps) => {
      const node = props.element;
      if (node.metadata?.type === 'file' && onFileSelect) {
        onFileSelect(node.metadata.path as string);
      }
    },
    [onFileSelect],
  );

  const handleExpand = useCallback((props: { element: INode; isExpanded: boolean }) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (props.isExpanded) {
        next.add(String(props.element.id));
      } else {
        next.delete(String(props.element.id));
      }
      return next;
    });
  }, []);

  if (!baseUrl) {
    return (
      <Box sx={styles.container}>
        {!hideHeader && (
          <Box sx={styles.header}>
            <Typography sx={styles.title}>Explorer</Typography>
          </Box>
        )}
        <Box sx={styles.empty}>No watcher available</Box>
      </Box>
    );
  }

  if (loading) {
    return (
      <Box sx={styles.container}>
        {!hideHeader && (
          <Box sx={styles.header}>
            <Typography sx={styles.title}>Explorer</Typography>
          </Box>
        )}
        <Box sx={styles.loading}>
          <CircularProgress size={20} sx={{ color: '#4ec9b0' }} />
        </Box>
      </Box>
    );
  }

  if (error) {
    return (
      <Box sx={styles.container}>
        {!hideHeader && (
          <Box sx={styles.header}>
            <Typography sx={styles.title}>Explorer</Typography>
          </Box>
        )}
        <Box sx={styles.error}>{error}</Box>
      </Box>
    );
  }

  if (treeData.length === 0) {
    return (
      <Box sx={styles.container}>
        {!hideHeader && (
          <Box sx={styles.header}>
            <Typography sx={styles.title}>Explorer</Typography>
          </Box>
        )}
        <Box sx={styles.empty}>No files in workspace</Box>
      </Box>
    );
  }

  return (
    <Box sx={styles.container}>
      {!hideHeader && (
        <Box sx={styles.header}>
          <Typography sx={styles.title}>Explorer</Typography>
        </Box>
      )}
      <Box sx={styles.treeContainer}>
        <TreeView
          data={flattenedData}
          aria-label="File explorer"
          onNodeSelect={handleNodeSelect}
          onExpand={handleExpand}
          expandedIds={Array.from(expandedIds)}
          selectedIds={selectedPath ? [selectedPath] : []}
          nodeRenderer={({ element, isBranch, isExpanded, getNodeProps, level }) => {
            // Use metadata.type to determine if it's a directory (handles empty folders)
            const isDirectory = element.metadata?.type === 'directory' || isBranch;
            const nodePath = element.metadata?.path || element.id;
            const isSelected = !isDirectory && nodePath === selectedPath;

            return (
              <div
                {...getNodeProps()}
                className={cx('tree-node', {
                  'tree-node--directory': isDirectory,
                  'tree-node--selected': isSelected,
                })}
                style={{ paddingLeft: `${(level - 1) * 16 + 8}px` }}
              >
                {isDirectory ? (
                  <>
                    <span className="tree-node__arrow">{isExpanded ? '▼' : '▶'}</span>
                    {isExpanded ? <FolderOpenIcon /> : <FolderIcon />}
                  </>
                ) : (
                  <>
                    <span className="tree-node__arrow" style={{ visibility: 'hidden' }}>
                      ▶
                    </span>
                    <FileIconComponent name={element.name} />
                  </>
                )}
                <span className="tree-node__name">{element.name}</span>
              </div>
            );
          }}
        />
      </Box>
    </Box>
  );
};
