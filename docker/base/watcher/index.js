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
 *
 * Upload server (UPLOAD_PORT, 4041): a POST stores an image pasted into the
 * browser terminal and answers with its path, which the page then types into the
 * CLI. A port of its own because Traefik routes it only for the session's owner;
 * the file server above is open to everyone the session is shared with.
 */

const { isUtf8 } = require('buffer');
const fs = require('fs');
const http = require('http');
const https = require('https');
const net = require('net');
const path = require('path');

// Loaded on first use so the pure helpers below can be unit-tested without
// the watcher's npm dependencies installed.
const chokidar = { watch: (...args) => require('chokidar').watch(...args) };

// Configuration
const PORT = parseInt(process.env.WATCHER_PORT || '4040', 10);
const WATCH_DIR = process.env.WATCH_DIR || '/workspace';
const UPLOAD_PORT = parseInt(process.env.UPLOAD_PORT || '4041', 10);
const VSCODE_SETTINGS_PATH = process.env.VSCODE_SETTINGS_PATH || '/opt/openvscode-server/default-settings.json';
const UPLOAD_DIR = process.env.UPLOAD_DIR || '/tmp/aixle-uploads';
const UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
const UPLOAD_TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/gif': 'gif', 'image/webp': 'webp' };

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

// Credential write-back (agent + workflow-step sessions; never auth_setup).
// The CLI in this container renews its own tokens. Without this the platform only learns
// about it at session cleanup, so a container killed by an OOM or an eviction takes the
// rotation with it and leaves the stored refresh token one the vendor has already rotated
// out. Reporting each change makes the stored credential the copy every holder shares.
const CREDENTIAL_SYNC_URL = process.env.CREDENTIAL_SYNC_URL || null;
const CREDENTIAL_SYNC_KEY = process.env.CREDENTIAL_SYNC_KEY || null;
const CREDENTIAL_SYNC_PATHS = (process.env.CREDENTIAL_SYNC_PATHS || '')
  .split(',')
  .map((p) => p.trim())
  .filter(Boolean);
const SESSION_ID = process.env.SESSION_ID || null;
// A CLI writes its credential file as part of a burst (write, rename, chmod); wait for the
// burst to settle rather than posting three times.
const CREDENTIAL_SYNC_DEBOUNCE_MS = 3000;
// Floor between two posts. A pathological writer cannot turn this into a request loop.
const CREDENTIAL_SYNC_MIN_INTERVAL_MS = 15000;
// The file is small (Claude's is well under 4 KB) and the server refuses more.
const CREDENTIAL_SYNC_MAX_BYTES = 256 * 1024;

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
  const binaryExts = ['zip', 'tar', 'gz', 'rar', '7z', 'exe', 'dll', 'so', 'dylib', 'bin', 'dat', 'sqlite', 'sqlite3', 'db'];
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
 * Resolve a client-supplied path inside `root`, or return null when it escapes.
 * A plain prefix test lets `/workspace-x` through for `/workspace`, and a
 * symlink planted inside the workspace can point anywhere, so both the lexical
 * path and its real target have to stay under the root.
 */
function resolveInside(root, requested) {
  const base = path.resolve(root);
  const candidate = path.resolve(base, requested);
  const inside = (p, r) => p === r || p.startsWith(r + path.sep);
  if (!inside(candidate, base)) return null;

  try {
    const realBase = fs.realpathSync(base);
    const realCandidate = fs.realpathSync(candidate);
    if (!inside(realCandidate, realBase)) return null;
  } catch (e) {
    if (e.code !== 'ENOENT') return null;
  }
  return candidate;
}

/**
 * Where /preload may send the browser: somewhere on the host that served the
 * preload page, under the /t/ routes. Anything else — another host, `//evil`,
 * `javascript:` — is refused, so the page cannot be used as an open redirect.
 */
function safePreloadTarget(to, requestHost) {
  if (!to || !requestHost) return null;
  let target;
  try {
    target = new URL(to, `http://${requestHost}`);
  } catch (e) {
    return null;
  }
  if (!['http:', 'https:'].includes(target.protocol)) return null;
  if (target.host !== requestHost) return null;
  if (!target.pathname.startsWith('/t/')) return null;
  return target.href;
}

const VSCODE_THEMES = { light: 'Default Light Modern', dark: 'Default Dark Modern' };

/**
 * The image's VS Code settings with the theme for `scheme`, or null without them.
 */
function vscodeUserSettings(scheme, settingsPath = VSCODE_SETTINGS_PATH) {
  try {
    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf-8'));
    settings['workbench.colorTheme'] = VSCODE_THEMES[scheme] || VSCODE_THEMES.dark;
    return JSON.stringify(settings, null, 2);
  } catch (e) {
    log.warn(`No VS Code settings at ${settingsPath}: ${e.message}`);
    return null;
  }
}

function sendHtml(res, title, script) {
  const html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>${title}</title>
<style>body{margin:0;background:#1e1e1e;display:flex;align-items:center;justify-content:center;height:100vh;color:#ccc;font-family:sans-serif;font-size:14px}</style>
</head>
<body>
<span>${title}</span>
<script>${script}</script>
</body>
</html>`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.writeHead(200);
  res.end(html);
}

const inlineJson = (value) => JSON.stringify(value).replace(/</g, '\\u003c');

/**
 * Browser-side script of /preload (reset, then open VS Code) and /theme (settings only).
 *
 * VS Code in the browser keeps USER settings in IndexedDB, not in the server's
 * data dir, and ignores application-scoped keys (theme, startup editor) in the
 * Machine settings it does read. Its per-workspace state lives in a database
 * named after the folder URI, whose authority is location.host — port included.
 * Every session reuses that same URI, so without a reset it reopens the editors
 * of an earlier session, files that may not exist in this one.
 */
function vscodeStateScript({ settings, redirectTo }) {
  const resetWorkspace = redirectTo !== null;
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

  return `
(async () => {
  const emptyEditorState = ${inlineJson(emptyEditorState)};
  const userSettings = ${inlineJson(settings)};
  const resetWorkspace = ${resetWorkspace};
  const redirectTo = ${inlineJson(redirectTo)};

  const done = (req) => new Promise((resolve) => { req.onsuccess = () => resolve(req.result); req.onerror = () => resolve(null); req.onblocked = () => resolve(null); });

  const patchState = async (name, clear) => {
    const req = indexedDB.open(name, 1);
    req.onupgradeneeded = () => { req.result.createObjectStore('ItemTable'); };
    const db = await done(req);
    if (!db) return;
    const store = db.objectStoreNames.contains('ItemTable') ? 'ItemTable' : db.objectStoreNames[0];
    if (!store) { db.close(); return; }
    const tx = db.transaction(store, 'readwrite');
    const s = tx.objectStore(store);
    if (clear) s.clear();
    s.put(emptyEditorState, 'memento/workbench.parts.editor');
    s.put('true', 'workbench.auxiliaryBar.hidden');
    s.put('true', 'workbench.auxiliaryBar.empty');
    s.put('true', 'workbench.activityBar.hidden');
    s.put(JSON.stringify([{id:'workbench.panel.chat',pinned:true,visible:false,order:1},{id:'workbench.viewContainer.agentSessions',pinned:true,visible:false,order:6}]), 'workbench.auxiliarybar.pinnedPanels');
    s.put(JSON.stringify([{id:'workbench.panel.chat',visible:false},{id:'workbench.viewContainer.agentSessions',visible:false}]), 'workbench.auxiliarybar.viewContainersWorkspaceState');
    await new Promise((resolve) => { tx.oncomplete = resolve; tx.onerror = resolve; });
    db.close();
  };

  // Store names are the ones VS Code 1.106 creates at version 3; a database made
  // here must already hold all three.
  const writeUserSettings = async () => {
    if (!userSettings) return;
    const req = indexedDB.open('vscode-web-db', 3);
    req.onupgradeneeded = () => {
      for (const name of ['vscode-userdata-store', 'vscode-logs-store', 'vscode-filehandles-store']) {
        if (!req.result.objectStoreNames.contains(name)) req.result.createObjectStore(name);
      }
    };
    const db = await done(req);
    if (!db) return;
    if (db.objectStoreNames.contains('vscode-userdata-store')) {
      const tx = db.transaction('vscode-userdata-store', 'readwrite');
      tx.objectStore('vscode-userdata-store').put(new TextEncoder().encode(userSettings), '/User/settings.json');
      await new Promise((resolve) => { tx.oncomplete = resolve; tx.onerror = resolve; });
    }
    db.close();
    // What VS Code's own IndexedDB file provider posts, so an open editor reloads its settings.
    try {
      const channel = new BroadcastChannel('vscode.indexedDB.vscode-userdata.changes');
      channel.postMessage([{ type: 0, resource: { scheme: 'vscode-userdata', authority: '', path: '/User/settings.json', query: '', fragment: '' } }]);
      channel.close();
    } catch (e) {}
  };

  try {
    // VS Code's own hash of the folder URI (stringHash in base/common/hash.ts).
    function numberHash(val, h) { return (((h << 5) - h) + val) | 0; }
    function stringHash(s, h) {
      h = numberHash(149417, h);
      for (let i = 0; i < s.length; i++) h = numberHash(s.charCodeAt(i), h);
      return h;
    }
    const workspaceDbName = 'vscode-web-state-db-' + stringHash('vscode-remote://' + location.host + '/workspace', 0).toString(16);

    // Cleared, not deleted: every session's editor is on the same origin and folder
    // URI, so another tab's VS Code may hold this database open — a delete would
    // wait for it (and hang this page) and then cut that editor off.
    const work = Promise.all([
      resetWorkspace ? patchState('vscode-web-state-db-global', false) : null,
      resetWorkspace ? patchState(workspaceDbName, true) : null,
      writeUserSettings(),
    ]);
    // Never keep the editor from opening over a database that does not answer.
    await Promise.race([work, new Promise((resolve) => setTimeout(resolve, 3000))]);
  } catch (e) {}

  if (redirectTo) window.location.replace(redirectTo);
})();
`;
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

    const fullPath = resolveInside(WATCH_DIR, filePath);
    if (!fullPath) {
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

  // Preload page: resets VS Code's browser state, then redirects to VS Code.
  // Served at the same traefik origin as VS Code so IndexedDB is shared.
  if (url.pathname === '/preload') {
    const to = safePreloadTarget(url.searchParams.get('to'), req.headers.host);
    if (!to) {
      res.writeHead(400);
      res.end('Missing or invalid ?to= parameter');
      return;
    }
    sendHtml(res, 'Loading editor...', vscodeStateScript({ settings: vscodeUserSettings(url.searchParams.get('scheme')), redirectTo: to }));
    return;
  }

  // Switches an open VS Code between light and dark. The session page loads it in a
  // hidden frame when the app changes theme; VS Code reloads its settings on the
  // change notification, so the editor is not reopened and unsaved work survives.
  if (url.pathname === '/theme') {
    sendHtml(res, 'Theme', vscodeStateScript({ settings: vscodeUserSettings(url.searchParams.get('scheme')), redirectTo: null }));
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
 * Returns true if any of the JSON keys exist in config, or if ALL of the
 * `__contains__:` markers appear in it
 */
function checkAuthComplete(configContent, requiredKeys = AUTH_REQUIRED_KEYS) {
  if (requiredKeys.length === 0) {
    log.warn('AUTH_REQUIRED_KEYS not set, cannot detect auth completion');
    return false;
  }

  // `__present__` sentinel: the watched file existing with non-empty content IS the
  // completion signal — no JSON key check. Used when the credential is an opaque or
  // encrypted blob (e.g. Gemini's gemini-credentials.json), and to avoid matching a
  // config file written at auth-METHOD selection (before the credential is entered),
  // which would otherwise report success prematurely and close the auth container.
  if (requiredKeys.includes('__present__')) {
    return typeof configContent === 'string' && configContent.trim().length > 0;
  }

  // `__contains__:<text>` sentinel: the watched file contains this literal text. For
  // credentials that are neither JSON nor "created only on success" — Kiro CLI keeps
  // its login in a SQLite database that exists from the CLI's first run, and writes a
  // device-registration row as soon as the device code is displayed. Only the finished
  // login adds the token payload, whose OAuth field names (`access_token`,
  // `refresh_token`) appear verbatim in the file's bytes and are the same whichever
  // login method the user picked — unlike the row's key, which is named after it
  // (`kirocli:odic:token` for Builder ID, `kirocli:social:token` for a social login).
  // Measured on CLI 2.21.3: absent before and DURING the flow, present after.
  // Every marker must be present: an organisation login writes the token first and the
  // selected profile (`api.codewhisperer.profile`) only after a further prompt, and a
  // login closed between the two fails every later session with "No profile selected".
  // Agents::KiroCliAdapter#auth_complete? runs the same check server-side.
  const containsKeys = requiredKeys.filter((k) => k.startsWith('__contains__:'));
  if (containsKeys.length > 0) {
    if (typeof configContent !== 'string') return false;
    return containsKeys.every((k) => configContent.includes(k.slice('__contains__:'.length)));
  }

  try {
    const config = JSON.parse(configContent);

    // Check if ANY of the required keys exist and have a truthy value
    const foundKey = requiredKeys.find((key) => {
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
 * Loopback forwarder for an MCP server that is only reachable over the container
 * network.
 *
 * Kiro CLI's V3 agent refuses a plain-HTTP MCP server unless its host is loopback —
 * `host must be 127.0.0.1 or localhost, got ...`, from its own source — and the
 * platform's MCP endpoint is an internal service (`http://web:4002/action_mcp` in
 * development, a cluster address in production), not HTTPS. Rather than terminate TLS
 * on an internal hop, the agent container forwards 127.0.0.1:<port> to it, so the URL
 * the CLI is given is a loopback one and the bytes still go to the same place.
 *
 * Inert unless MCP_FORWARD_PORT and MCP_FORWARD_TARGET are both set, so only the
 * runtimes that need it pay for it.
 */
function startMcpForwarder() {
  const port = parseInt(process.env.MCP_FORWARD_PORT || '', 10);
  const target = (process.env.MCP_FORWARD_TARGET || '').trim();
  if (!port || !target) return;

  const separator = target.lastIndexOf(':');
  const targetHost = target.slice(0, separator);
  const targetPort = parseInt(target.slice(separator + 1), 10);
  if (!targetHost || !targetPort) {
    log.error(`MCP forwarder: cannot parse MCP_FORWARD_TARGET "${target}"`);
    return;
  }

  net
    .createServer((client) => {
      const upstream = net.connect(targetPort, targetHost);
      client.pipe(upstream);
      upstream.pipe(client);
      // A dead peer on either side must not take the watcher down with it.
      client.on('error', () => upstream.destroy());
      upstream.on('error', () => client.destroy());
    })
    .on('error', (err) => log.error(`MCP forwarder failed: ${err.message}`))
    .listen(port, '127.0.0.1', () => log.info(`MCP forwarder: 127.0.0.1:${port} -> ${targetHost}:${targetPort}`));
}

/**
 * Credential write-back: post the current contents of the agent's auth files to the
 * platform whenever one of them changes.
 *
 * Failures are logged and dropped: this is a best-effort report, session cleanup still
 * collects the same files, and nothing the agent is doing should stop because the platform
 * was briefly unreachable.
 */
function startCredentialSync() {
  if (!CREDENTIAL_SYNC_URL || !CREDENTIAL_SYNC_KEY || !SESSION_ID || CREDENTIAL_SYNC_PATHS.length === 0) {
    return;
  }

  const endpoint = new URL(CREDENTIAL_SYNC_URL);
  const transport = endpoint.protocol === 'https:' ? https : http;
  let timer = null;
  let lastPostAt = 0;
  let lastPayload = null;

  // A file that is not UTF-8 (Kiro's login is a SQLite database) travels as base64:
  // decoding it as text replaces every invalid byte, and the platform would store a
  // database the CLI can no longer open.
  function collect() {
    const files = {};
    const filesB64 = {};
    for (const filePath of CREDENTIAL_SYNC_PATHS) {
      try {
        const stats = fs.statSync(filePath);
        if (!stats.isFile() || stats.size === 0 || stats.size > CREDENTIAL_SYNC_MAX_BYTES) continue;
        const content = fs.readFileSync(filePath);
        if (isUtf8(content)) files[filePath] = content.toString('utf8');
        else filesB64[filePath] = content.toString('base64');
      } catch (e) {
        // Absent or unreadable: nothing to report for this path.
      }
    }
    return { files, filesB64 };
  }

  function post() {
    const { files, filesB64 } = collect();
    const count = Object.keys(files).length + Object.keys(filesB64).length;
    if (count === 0) return;

    // Unchanged content is not news. The CLI rewrites these files for reasons other than a
    // rotation, and every post takes a row lock on the credential.
    const payload = Object.keys(filesB64).length > 0 ? { files, files_b64: filesB64 } : { files };
    const body = JSON.stringify(payload);
    if (body === lastPayload) return;

    const request = transport.request(
      {
        hostname: endpoint.hostname,
        port: endpoint.port || (endpoint.protocol === 'https:' ? 443 : 80),
        path: endpoint.pathname,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
          'X-Session-Id': SESSION_ID,
          'X-Agent-Key': CREDENTIAL_SYNC_KEY,
        },
        timeout: 10000,
      },
      (res) => {
        res.resume();
        if (res.statusCode >= 200 && res.statusCode < 300) {
          lastPayload = body;
          log.info(`Credential sync: reported ${count} file(s)`);
        } else {
          log.warn(`Credential sync rejected: HTTP ${res.statusCode}`);
        }
      },
    );

    request.on('timeout', () => request.destroy(new Error('timeout')));
    request.on('error', (e) => log.warn(`Credential sync failed: ${e.message}`));
    request.write(body);
    request.end();
    lastPostAt = Date.now();
  }

  function schedule() {
    if (timer) clearTimeout(timer);
    const sinceLast = Date.now() - lastPostAt;
    const delay = Math.max(CREDENTIAL_SYNC_DEBOUNCE_MS, CREDENTIAL_SYNC_MIN_INTERVAL_MS - sinceLast);
    timer = setTimeout(post, delay);
  }

  // usePolling: the auth file lives outside /workspace, on a layer chokidar's native
  // watcher does not always deliver events for inside a container.
  const credentialWatcher = chokidar.watch(CREDENTIAL_SYNC_PATHS, {
    ignoreInitial: true,
    usePolling: true,
    interval: 5000,
    awaitWriteFinish: { stabilityThreshold: 1000, pollInterval: 200 },
  });

  credentialWatcher.on('all', (event) => {
    if (event === 'unlink') return;
    schedule();
  });
  credentialWatcher.on('error', (e) => log.warn(`Credential watcher error: ${e.message}`));

  log.info(`Credential sync watching ${CREDENTIAL_SYNC_PATHS.join(', ')}`);
}

/**
 * Name for an uploaded image, or null for a type an agent CLI cannot attach.
 */
function uploadFileName(contentType, now = new Date(), random = Math.random) {
  const ext = UPLOAD_TYPES[String(contentType || '').split(';')[0].trim().toLowerCase()];
  if (!ext) return null;
  const stamp = now.toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
  const suffix = Math.floor(random() * 0x10000).toString(16).padStart(4, '0');
  return `paste-${stamp}-${suffix}.${ext}`;
}

function handleUpload(req, res) {
  const reply = (status, body) => {
    res.setHeader('Content-Type', 'application/json');
    res.writeHead(status);
    res.end(JSON.stringify(body));
  };
  if (req.method !== 'POST') return reply(405, { error: 'Method not allowed' });

  const name = uploadFileName(req.headers['content-type']);
  if (!name) return reply(415, { error: 'Only PNG, JPEG, GIF and WebP images can be pasted' });
  if (Number(req.headers['content-length']) > UPLOAD_MAX_BYTES) {
    return reply(413, { error: `Images are limited to ${formatFileSize(UPLOAD_MAX_BYTES)}` });
  }

  const chunks = [];
  let size = 0;
  let refused = false;
  req.on('data', (chunk) => {
    if (refused) return;
    size += chunk.length;
    if (size > UPLOAD_MAX_BYTES) {
      refused = true;
      reply(413, { error: `Images are limited to ${formatFileSize(UPLOAD_MAX_BYTES)}` });
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });
  req.on('end', () => {
    if (refused) return;
    if (size === 0) return reply(400, { error: 'Empty upload' });
    try {
      fs.mkdirSync(UPLOAD_DIR, { recursive: true, mode: 0o755 });
      const target = path.join(UPLOAD_DIR, name);
      // 0644: the watcher runs as root, the agent CLI that reads the file does not.
      fs.writeFileSync(target, Buffer.concat(chunks), { mode: 0o644 });
      log.info(`Stored pasted image ${target} (${formatFileSize(size)})`);
      reply(201, { path: target });
    } catch (err) {
      reply(500, { error: err.message });
    }
  });
}

/**
 * Main server setup
 */
function startServer() {
  startMcpForwarder();
  http.createServer(handleUpload).listen(UPLOAD_PORT, () => log.info(`Upload server on port ${UPLOAD_PORT}`));
  const server = http.createServer(handleRequest);
  const { WebSocketServer } = require('ws');
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

if (require.main === module) {
  startServer();
  startCredentialSync();
}

module.exports = { checkAuthComplete, resolveInside, safePreloadTarget, uploadFileName, vscodeUserSettings };
