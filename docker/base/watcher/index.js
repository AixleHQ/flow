/**
 * File System Watcher Service
 *
 * Provides:
 *   - WebSocket streaming of file system changes
 *   - HTTP API for file tree
 *   - Real-time directory structure updates
 *   - Auth status detection for auth_setup sessions
 *
 * Ports:
 *   - HTTP/WS: 4040 (configurable via WATCHER_PORT)
 *
 * WebSocket Messages:
 *   - { type: 'change', event: 'add|change|unlink|addDir|unlinkDir', path: string }
 *   - { type: 'tree', data: TreeNode[] }
 *   - { type: 'ready' }
 *
 * HTTP Endpoints:
 *   - GET /tree - Returns full directory tree as JSON
 *   - GET /file?path=... - Returns file content
 *   - GET /health - Health check
 *   - GET /auth - Check authentication status (for auth_setup sessions)
 */

const fs = require('fs');
const http = require('http');
const path = require('path');

const chokidar = require('chokidar');
const { WebSocketServer } = require('ws');

// Configuration
const PORT = parseInt(process.env.WATCHER_PORT || '4040', 10);
const WATCH_DIR = process.env.WATCH_DIR || '/workspace';

// Auth watcher configuration (from ContainerService)
// Only used for auth_setup session type
const SESSION_TYPE = process.env.SESSION_TYPE || null;
// Supports comma-separated list of paths — checks each in order, returns true if any has required keys
const AUTH_WATCH_PATHS = (process.env.AUTH_WATCH_PATH || '')
  .split(',')
  .map((p) => p.trim())
  .filter(Boolean);
const AUTH_WATCH_PATH = AUTH_WATCH_PATHS[0] || null; // kept for logging compat
const AGENT_TYPE = process.env.AGENT_TYPE || 'unknown';
// Comma-separated list of JSON keys to check for auth completion
// e.g. "oauthAccount,primaryApiKey" - auth is complete if ANY of these exist
const AUTH_REQUIRED_KEYS = (process.env.AUTH_REQUIRED_KEYS || '')
  .split(',')
  .map((k) => k.trim())
  .filter(Boolean);

/**
 * Format file size to human readable string
 */
function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Determine file type category based on extension
 */
function getFileType(ext) {
  const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'ico', 'bmp'];
  const pdfExts = ['pdf'];
  const binaryExts = ['zip', 'tar', 'gz', 'rar', '7z', 'exe', 'dll', 'so', 'dylib', 'bin', 'dat'];
  const videoExts = ['mp4', 'webm', 'avi', 'mov', 'mkv'];
  const audioExts = ['mp3', 'wav', 'ogg', 'flac', 'aac'];

  if (imageExts.includes(ext)) return 'image';
  if (pdfExts.includes(ext)) return 'pdf';
  if (videoExts.includes(ext)) return 'video';
  if (audioExts.includes(ext)) return 'audio';
  if (binaryExts.includes(ext)) return 'binary';
  return 'text';
}

/**
 * Get MIME type based on extension
 */
function getMimeType(ext) {
  const mimeTypes = {
    // Images
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    gif: 'image/gif',
    webp: 'image/webp',
    svg: 'image/svg+xml',
    ico: 'image/x-icon',
    bmp: 'image/bmp',
    // Documents
    pdf: 'application/pdf',
    // Video
    mp4: 'video/mp4',
    webm: 'video/webm',
    avi: 'video/x-msvideo',
    mov: 'video/quicktime',
    // Audio
    mp3: 'audio/mpeg',
    wav: 'audio/wav',
    ogg: 'audio/ogg',
    // Archives
    zip: 'application/zip',
    tar: 'application/x-tar',
    gz: 'application/gzip',
    // Text/Code
    txt: 'text/plain',
    html: 'text/html',
    css: 'text/css',
    js: 'text/javascript',
    ts: 'text/typescript',
    json: 'application/json',
    xml: 'application/xml',
    md: 'text/markdown',
    yaml: 'text/yaml',
    yml: 'text/yaml',
  };
  return mimeTypes[ext] || 'application/octet-stream';
}
const MAX_DEPTH = parseInt(process.env.WATCHER_MAX_DEPTH || '10', 10);
const IGNORE_PATTERNS = (process.env.WATCHER_IGNORE || '')
  .split(',')
  .filter(Boolean)
  .concat([
    '**/node_modules/**',
    '**/.git/**',
    '**/venv/**',
    '**/__pycache__/**',
    '**/.claude/**',
    '**/tmp/**',
    '**/cache/**',
    '**/*.log',
  ]);

// Colors for logging
const log = {
  info: (msg) => console.log(`\x1b[36m[watcher]\x1b[0m ${msg}`),
  warn: (msg) => console.log(`\x1b[33m[watcher]\x1b[0m ${msg}`),
  error: (msg) => console.log(`\x1b[31m[watcher]\x1b[0m ${msg}`),
};

/**
 * Build directory tree recursively
 */
function buildTree(dir, depth = 0) {
  if (depth > MAX_DEPTH) return [];

  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });

    return entries
      .filter((entry) => {
        // Skip hidden files and ignored patterns
        if (entry.name.startsWith('.')) return false;
        if (entry.name === 'node_modules') return false;
        if (entry.name === '__pycache__') return false;
        // Hide platform-injected agent context files from file tree
        if (['AGENTS.md', 'CLAUDE.md', 'CLAUDE.local.md', 'GEMINI.md'].includes(entry.name)) return false;
        return true;
      })
      .sort((a, b) => {
        // Directories first, then alphabetically
        if (a.isDirectory() && !b.isDirectory()) return -1;
        if (!a.isDirectory() && b.isDirectory()) return 1;
        return a.name.localeCompare(b.name);
      })
      .map((entry) => {
        const fullPath = path.join(dir, entry.name);
        const relativePath = path.relative(WATCH_DIR, fullPath);

        if (entry.isDirectory()) {
          return {
            name: entry.name,
            path: relativePath,
            type: 'directory',
            children: buildTree(fullPath, depth + 1),
          };
        }

        // Get file stats for additional info
        let size = 0;
        try {
          const stats = fs.statSync(fullPath);
          size = stats.size;
        } catch (e) {
          // Ignore stat errors
        }

        return {
          name: entry.name,
          path: relativePath,
          type: 'file',
          extension: path.extname(entry.name).slice(1) || null,
          size,
        };
      });
  } catch (err) {
    log.error(`Error reading directory ${dir}: ${err.message}`);
    return [];
  }
}

/**
 * HTTP request handler
 */
function handleRequest(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);

  // Handle /file endpoint with path parameter
  if (url.pathname === '/file') {
    const filePath = url.searchParams.get('path');
    if (!filePath) {
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(400);
      res.end(JSON.stringify({ error: 'Missing path parameter' }));
      return;
    }

    // Resolve full path and ensure it's within WATCH_DIR (security)
    const fullPath = path.resolve(WATCH_DIR, filePath);
    if (!fullPath.startsWith(path.resolve(WATCH_DIR))) {
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(403);
      res.end(JSON.stringify({ error: 'Access denied: path outside workspace' }));
      return;
    }

    try {
      const stats = fs.statSync(fullPath);
      if (stats.isDirectory()) {
        res.setHeader('Content-Type', 'application/json');
        res.writeHead(400);
        res.end(JSON.stringify({ error: 'Path is a directory, not a file' }));
        return;
      }

      // Check file size (limit to 10MB for safety)
      const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
      if (stats.size > MAX_FILE_SIZE) {
        res.setHeader('Content-Type', 'application/json');
        res.writeHead(413);
        res.end(
          JSON.stringify({
            error: 'File too large to display',
            message: `File size is ${formatFileSize(stats.size)}, maximum allowed is ${formatFileSize(MAX_FILE_SIZE)}`,
            size: stats.size,
            maxSize: MAX_FILE_SIZE,
          }),
        );
        return;
      }

      const ext = path.extname(fullPath).slice(1).toLowerCase();
      const fileType = getFileType(ext);
      const mimeType = getMimeType(ext);

      let content;
      let encoding = 'text';

      if (fileType === 'binary' || fileType === 'image' || fileType === 'pdf') {
        // Read as binary and encode to base64
        const buffer = fs.readFileSync(fullPath);
        content = buffer.toString('base64');
        encoding = 'base64';
      } else {
        // Read as text
        content = fs.readFileSync(fullPath, 'utf-8');
      }

      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);
      res.end(
        JSON.stringify({
          path: filePath,
          name: path.basename(fullPath),
          extension: ext,
          size: stats.size,
          content: content,
          encoding: encoding,
          fileType: fileType,
          mimeType: mimeType,
          mtime: stats.mtime.toISOString(),
        }),
      );
    } catch (err) {
      res.setHeader('Content-Type', 'application/json');
      if (err.code === 'ENOENT') {
        res.writeHead(404);
        res.end(JSON.stringify({ error: 'File not found' }));
      } else {
        res.writeHead(500);
        res.end(JSON.stringify({ error: err.message }));
      }
    }
    return;
  }

  // Preload page: patches VS Code IndexedDB then redirects to VS Code.
  // Served at the same traefik origin as VS Code so IndexedDB is shared.
  if (url.pathname === '/preload') {
    const to = url.searchParams.get('to');
    if (!to || (!to.startsWith('/') && !to.startsWith('http'))) {
      res.writeHead(400);
      res.end('Missing or invalid ?to= parameter');
      return;
    }

    const emptyEditorState = JSON.stringify({
      'editorpart.state': {
        serializedGrid: {
          root: {
            type: 'branch',
            data: [{ type: 'leaf', data: { id: 0, editors: [], mru: [], preview: -1 }, size: 863 }],
            size: 883,
          },
          orientation: 0,
          width: 883,
          height: 863,
        },
        activeGroup: 0,
        mostRecentActiveGroups: [0],
      },
    });

    const html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Loading editor...</title>
<style>body{margin:0;background:#1e1e1e;display:flex;align-items:center;justify-content:center;height:100vh;color:#ccc;font-family:sans-serif;font-size:14px}</style>
</head>
<body>
<span>Loading editor...</span>
<script>
(async () => {
  const emptyEditorState = ${JSON.stringify(emptyEditorState)};
  const patch = (name) => new Promise((resolve) => {
    const req = indexedDB.open(name, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore('ItemTable'); };
    req.onsuccess = () => {
      const db = req.result;
      const store = db.objectStoreNames.contains('ItemTable') ? 'ItemTable' : db.objectStoreNames[0];
      if (!store) { db.close(); resolve(); return; }
      const tx = db.transaction(store, 'readwrite');
      const s = tx.objectStore(store);
      s.put(emptyEditorState, 'memento/workbench.parts.editor');
      s.put('true', 'workbench.auxiliaryBar.hidden');
      s.put('true', 'workbench.auxiliaryBar.empty');
      s.put('true', 'workbench.activityBar.hidden');
      s.put(JSON.stringify([{id:'workbench.panel.chat',pinned:true,visible:false,order:1},{id:'workbench.viewContainer.agentSessions',pinned:true,visible:false,order:6}]), 'workbench.auxiliarybar.pinnedPanels');
      s.put(JSON.stringify([{id:'workbench.panel.chat',visible:false},{id:'workbench.viewContainer.agentSessions',visible:false}]), 'workbench.auxiliarybar.viewContainersWorkspaceState');
      tx.oncomplete = () => { db.close(); resolve(); };
      tx.onerror = () => { db.close(); resolve(); };
    };
    req.onerror = () => resolve();
  });

  try {
    // Compute the workspace-specific DB name using VS Code's own hash algorithm:
    // hash = stringHash("vscode-remote://{hostname}/workspace", 0).toString(16)
    function numberHash(val, h) { return (((h << 5) - h) + val) | 0; }
    function stringHash(s, h) {
      h = numberHash(149417, h);
      for (let i = 0; i < s.length; i++) h = numberHash(s.charCodeAt(i), h);
      return h;
    }
    const folderUri = 'vscode-remote://' + window.location.hostname + '/workspace';
    const workspaceDbName = 'vscode-web-state-db-' + stringHash(folderUri, 0).toString(16);

    await Promise.all(['vscode-web-state-db-global', workspaceDbName].map(patch));
  } catch(e) {}

  window.location.replace(${JSON.stringify(to)});
})();
</script>
</body>
</html>`;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.writeHead(200);
    res.end(html);
    return;
  }

  switch (url.pathname) {
    case '/tree':
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);
      res.end(
        JSON.stringify({
          root: WATCH_DIR,
          tree: buildTree(WATCH_DIR),
          timestamp: Date.now(),
        }),
      );
      break;

    case '/health':
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);
      res.end(JSON.stringify({ status: 'ok', watching: WATCH_DIR }));
      break;

    case '/auth':
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);

      // Simple response: just authenticated true/false
      let authenticated = false;

      if (SESSION_TYPE === 'auth_setup' && AUTH_WATCH_PATHS.length > 0) {
        for (const watchPath of AUTH_WATCH_PATHS) {
          try {
            if (fs.existsSync(watchPath)) {
              const content = fs.readFileSync(watchPath, 'utf-8');
              if (checkAuthComplete(content)) {
                authenticated = true;
                break;
              }
            }
          } catch (e) {
            log.error(`Error checking auth status at ${watchPath}: ${e.message}`);
          }
        }
      }

      res.end(JSON.stringify({ authenticated }));
      break;

    default:
      res.writeHead(404);
      res.end('Not Found');
  }
}

/**
 * Auth detection logic
 * Returns true if any of AUTH_REQUIRED_KEYS exist in config
 */
function checkAuthComplete(configContent) {
  if (AUTH_REQUIRED_KEYS.length === 0) {
    log.warn('AUTH_REQUIRED_KEYS not set, cannot detect auth completion');
    return false;
  }

  try {
    const config = JSON.parse(configContent);

    // Check if ANY of the required keys exist and have a truthy value
    const foundKey = AUTH_REQUIRED_KEYS.find((key) => {
      // Support nested keys like "oauthAccount.accountUuid"
      const value = key.split('.').reduce((obj, k) => obj?.[k], config);
      return value !== undefined && value !== null && value !== '';
    });

    if (foundKey) {
      log.info(`Auth key found: ${foundKey}`);
      return true;
    }

    return false;
  } catch (e) {
    log.error(`Failed to parse config: ${e.message}`);
    return false;
  }
}

/**
 * Main server setup
 */
function startServer() {
  const server = http.createServer(handleRequest);
  const wss = new WebSocketServer({ server });

  // Track connected clients
  const clients = new Set();

  // Broadcast to all connected clients
  function broadcast(message) {
    const data = JSON.stringify(message);
    for (const client of clients) {
      if (client.readyState === 1) {
        // WebSocket.OPEN
        client.send(data);
      }
    }
  }

  // Setup file watcher
  const watcher = chokidar.watch(WATCH_DIR, {
    ignored: IGNORE_PATTERNS,
    persistent: true,
    ignoreInitial: true,
    depth: MAX_DEPTH,
    awaitWriteFinish: {
      stabilityThreshold: 100,
      pollInterval: 500,
    },
  });

  // File system event handlers
  const events = ['add', 'change', 'unlink', 'addDir', 'unlinkDir'];
  events.forEach((event) => {
    watcher.on(event, (filePath) => {
      const relativePath = path.relative(WATCH_DIR, filePath);
      log.info(`${event}: ${relativePath}`);

      broadcast({
        type: 'change',
        event,
        path: relativePath,
        timestamp: Date.now(),
      });

      // For structural changes, also send updated tree
      if (['add', 'unlink', 'addDir', 'unlinkDir'].includes(event)) {
        // Debounce tree updates
        clearTimeout(startServer.treeTimeout);
        startServer.treeTimeout = setTimeout(() => {
          broadcast({
            type: 'tree',
            data: buildTree(WATCH_DIR),
            timestamp: Date.now(),
          });
        }, 200);
      }
    });
  });

  watcher.on('ready', () => {
    log.info(`Watching ${WATCH_DIR} (depth: ${MAX_DEPTH})`);
  });

  watcher.on('error', (error) => {
    log.error(`Watcher error: ${error.message}`);
  });

  // WebSocket connection handler
  wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    log.info(`Client connected: ${clientIp}`);
    clients.add(ws);

    // Send initial tree
    ws.send(
      JSON.stringify({
        type: 'tree',
        data: buildTree(WATCH_DIR),
        timestamp: Date.now(),
      }),
    );

    ws.send(JSON.stringify({ type: 'ready' }));

    // Handle client messages
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());

        // Handle tree request
        if (message.type === 'getTree') {
          ws.send(
            JSON.stringify({
              type: 'tree',
              data: buildTree(WATCH_DIR),
              timestamp: Date.now(),
            }),
          );
        }
      } catch (e) {
        // Ignore invalid messages
      }
    });

    ws.on('close', () => {
      log.info(`Client disconnected: ${clientIp}`);
      clients.delete(ws);
    });

    ws.on('error', (error) => {
      log.error(`WebSocket error: ${error.message}`);
      clients.delete(ws);
    });
  });

  // Start listening
  server.listen(PORT, '0.0.0.0', () => {
    log.info(`File watcher server started on port ${PORT}`);
    log.info(`  HTTP: http://0.0.0.0:${PORT}/tree`);
    log.info(`  WS:   ws://0.0.0.0:${PORT}`);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    log.info('Shutting down...');
    watcher.close();
    server.close();
    process.exit(0);
  });

  process.on('SIGINT', () => {
    log.info('Shutting down...');
    watcher.close();
    server.close();
    process.exit(0);
  });
}

// Start the server
startServer();
