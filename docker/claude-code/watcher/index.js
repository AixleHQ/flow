/**
 * File System Watcher Service
 *
 * Provides:
 *   - WebSocket streaming of file system changes
 *   - HTTP API for file tree
 *   - Real-time directory structure updates
 *
 * Ports:
 *   - HTTP/WS: 4000 (configurable via WATCHER_PORT)
 *
 * WebSocket Messages:
 *   - { type: 'change', event: 'add|change|unlink|addDir|unlinkDir', path: string }
 *   - { type: 'tree', data: TreeNode[] }
 *   - { type: 'ready' }
 *
 * HTTP Endpoints:
 *   - GET /tree - Returns full directory tree as JSON
 *   - GET /health - Health check
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const chokidar = require('chokidar');

// Configuration
const PORT = parseInt(process.env.WATCHER_PORT || '4000', 10);
const WATCH_DIR = process.env.WATCH_DIR || '/workspace';
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
      .filter(entry => {
        // Skip hidden files and ignored patterns
        if (entry.name.startsWith('.')) return false;
        if (entry.name === 'node_modules') return false;
        if (entry.name === '__pycache__') return false;
        return true;
      })
      .sort((a, b) => {
        // Directories first, then alphabetically
        if (a.isDirectory() && !b.isDirectory()) return -1;
        if (!a.isDirectory() && b.isDirectory()) return 1;
        return a.name.localeCompare(b.name);
      })
      .map(entry => {
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

  switch (url.pathname) {
    case '/tree':
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);
      res.end(JSON.stringify({
        root: WATCH_DIR,
        tree: buildTree(WATCH_DIR),
        timestamp: Date.now(),
      }));
      break;

    case '/health':
      res.setHeader('Content-Type', 'application/json');
      res.writeHead(200);
      res.end(JSON.stringify({ status: 'ok', watching: WATCH_DIR }));
      break;

    default:
      res.writeHead(404);
      res.end('Not Found');
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
      if (client.readyState === 1) { // WebSocket.OPEN
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
      pollInterval: 50,
    },
  });

  // File system event handlers
  const events = ['add', 'change', 'unlink', 'addDir', 'unlinkDir'];
  events.forEach(event => {
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
    ws.send(JSON.stringify({
      type: 'tree',
      data: buildTree(WATCH_DIR),
      timestamp: Date.now(),
    }));

    ws.send(JSON.stringify({ type: 'ready' }));

    // Handle client messages
    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());

        // Handle tree request
        if (message.type === 'getTree') {
          ws.send(JSON.stringify({
            type: 'tree',
            data: buildTree(WATCH_DIR),
            timestamp: Date.now(),
          }));
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
