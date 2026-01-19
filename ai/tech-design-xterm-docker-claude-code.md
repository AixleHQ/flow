# Technical Design: xterm.js + Docker + Claude Code

**Date:** 2026-01-16
**Author:** Artem Petrov
**Status:** ✅ Implemented (with modifications)
**Related:** [interactive-agent-architecture-v2-claude-code-2026-01-16.md](./interactive-agent-architecture-v2-claude-code-2026-01-16.md)
**Last Updated:** 2026-01-20

---

## 🎯 Goal

Implement an interactive in-browser terminal connected to a Docker container with the Claude Code CLI.

---

## 📊 Implementation Status Summary

| Task | Status | Notes |
|------|--------|-------|
| Task 1: xterm.js component | ✅ **Replaced with ttyd** | Used ttyd instead of xterm.js for simplicity |
| Task 2: Docker socket + Container management | ✅ **Done** | `ContainerManager` implemented |
| Task 3: WebSocket connection | ✅ **Replaced with iframe** | ttyd provides its own WebSocket |
| Task 4: Docker image with Claude Code | ✅ **Done** | `claude-code:latest` image |
| Task 5: ANTHROPIC_API_KEY | ✅ **Done** | Via environment variables |
| **Additional:** File Watcher | ✅ **Done** | WebSocket + HTTP for the file tree |
| **Additional:** File Tree UI | ✅ **Done** | react-accessible-treeview + react-file-icon |
| **Additional:** File Viewer | ✅ **Done** | CodeMirror + react-pdf + images |

---

## 📋 Tasks Breakdown

### Task 1: xterm.js component with React

**Status:** ✅ **Replaced with ttyd**

**Solution:** Instead of building our own xterm.js component with WebSocket, we used [ttyd](https://github.com/tsl0922/ttyd) — a ready-made solution that:
- Provides a web terminal out of the box
- Works through an iframe
- Does not require writing WebSocket logic

**Implementation:**
- `docker/claude-code/Dockerfile` — ttyd installed in the image
- `docker/claude-code/entrypoint.sh` — ttyd runs on port 7681
- `web/app/frontend/pages/session/ui/SessionPage.tsx` — iframe with ttyd

**Acceptance Criteria:**
- [x] Terminal renders in the DOM (via iframe)
- [x] User can type text
- [x] Terminal automatically adjusts to the container size
- [x] ~~Clickable links work~~ (not verified)

---

### Task 2: Docker socket + Container management in Rails

**Status:** ✅ **Done**

**Files:**
- `web/app/services/container_manager.rb` — container management
- `web/app/controllers/api/v1/terminal_sessions_controller.rb` — API endpoints

**Changes from the plan:**
- Used a `mode` parameter instead of `interactive`
- Added support for multiple modes: `claude_code`, `interactive`, `dev`
- Containers are named as `palad-{session_id}-{mode}`
- Ports are mapped dynamically (ttyd: 7681, watcher: 4040)

**Acceptance Criteria:**
- [x] Docker socket is accessible from the Rails container
- [x] `ContainerManager.create_session` creates a container
- [x] `ContainerManager.stop_session` stops and removes the container
- [x] Container ID and ports are stored in Redis

---

### Task 3: WebSocket connection of xterm to the Docker PTY

**Status:** ✅ **Replaced with iframe + ttyd**

**Solution:** Instead of our own ActionCable channel for the PTY, we use ttyd which:
- Manages the WebSocket connection itself
- Provides a full-featured terminal over HTTP/WS
- Embeds into the page via an iframe

**Implementation:**
```tsx
// SessionPage.tsx
<iframe
  src={`http://localhost:${ttydPort}`}
  style={{ width: '100%', height: '100%' }}
  title="Terminal"
/>
```

**Acceptance Criteria:**
- [x] ~~WebSocket connection is established~~ (ttyd manages it)
- [x] User input is forwarded to the container
- [x] Container output is displayed in the terminal
- [x] Terminal resize works

---

### Task 4: Docker image with the Claude Code CLI

**Status:** ✅ **Done**

**Files:**
- `docker/claude-code/Dockerfile`
- `docker/claude-code/entrypoint.sh`
- `docker/claude-code/watcher/` — File watcher service
- `docker/claude-code/config/` — Claude Code configuration
- `docker/claude-code/prompts/` — BMAD prompts

**Changes from the plan:**
- Base image: `node:22-alpine` instead of `node:20-slim`
- Added ttyd for the web terminal
- Added File Watcher (Node.js + chokidar + ws)
- Added configuration for non-interactive Claude Code startup:
  - `/etc/claude-code/managed-settings.json` — forceLoginMethod: "console"
  - `/home/claude/.claude.json` — hasCompletedOnboarding: true

**Acceptance Criteria:**
- [x] Image builds without errors
- [x] Claude Code CLI is available (`claude --version`)
- [x] CLAUDE.md is copied from prompts/
- [x] ~~settings.json is created with the correct permissions~~ (we use managed-settings.json)
- [x] Claude Code starts without interactive prompts about subscription/theme

---

### Task 5: ANTHROPIC_API_KEY in the environment

**Status:** ✅ **Done**

**Implementation:**
- `docker-compose.yml` — ANTHROPIC_API_KEY is passed to the web service
- `ContainerManager` passes the key to the created containers

**Acceptance Criteria:**
- [x] `.env` file is not in git
- [x] `.env.example` contains a template
- [x] Rails reads ANTHROPIC_API_KEY from ENV
- [x] Container receives the API key via the environment

---

## ✅ Additional Features Implemented

### File Watcher Service

**Status:** ✅ **Done**

**Files:**
- `docker/claude-code/watcher/index.js`
- `docker/claude-code/watcher/package.json`

**Functionality:**
- HTTP endpoint `/tree` — returns the file tree
- HTTP endpoint `/file?path=...` — returns the file contents
- WebSocket — streams file system changes in real time
- File size limit: 10MB
- Supported types: text/code, images (jpg, png, gif, webp, svg), PDF

---

### File Tree UI Component

**Status:** ✅ **Done**

**Files:**
- `web/app/frontend/features/file-tree/ui/FileTree.tsx`
- `web/app/frontend/features/file-tree/ui/FileTree.css`

**Functionality:**
- Rendering the file tree using `react-accessible-treeview`
- File icons using `react-file-icon`
- Automatic expansion of all folders
- Real-time updates on file system changes
- Highlighting the selected file

---

### File Viewer Component

**Status:** ✅ **Done**

**Files:**
- `web/app/frontend/features/file-tree/ui/FileViewer.tsx`

**Functionality:**
- Code viewing with syntax highlighting (CodeMirror)
- Image viewing (jpg, png, gif, webp, svg)
- PDF viewing with pagination (react-pdf)
- File size limit of 10MB with a clear error message
- Resizable panels (react-resizable-panels)

---

### Session Page Layout

**Status:** ✅ **Done**

**File:** `web/app/frontend/pages/session/ui/SessionPage.tsx`

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Header: Session info, status, controls                       │
├──────────┬──────────────────────────────────────────────────┤
│          │                                                   │
│ FileTree │  FileViewer (optional)  │  Terminal (ttyd)       │
│ (sidebar)│  ◀──── resizable ────▶  │                        │
│          │                                                   │
└──────────┴──────────────────────────────────────────────────┘
```

---

## 📊 Final Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           BROWSER                                │
│  React UI with:                                                  │
│  - FileTree (react-accessible-treeview + react-file-icon)       │
│  - FileViewer (CodeMirror + react-pdf + images)                 │
│  - Terminal (ttyd iframe)                                        │
│  - Resizable panels (react-resizable-panels)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
┌─────────────────────────┐   ┌─────────────────────────┐
│         RAILS           │   │    DOCKER CONTAINER     │
│  • REST API             │   │    (claude-code:latest) │
│  • ContainerManager     │   │                         │
│  • Session management   │   │    ┌─────────────────┐  │
│                         │   │    │ ttyd (7681)     │  │
│                         │   │    │ Web Terminal    │  │
└─────────────────────────┘   │    └─────────────────┘  │
                              │                         │
                              │    ┌─────────────────┐  │
                              │    │ Watcher (4040)  │  │
                              │    │ File tree + WS  │  │
                              │    └─────────────────┘  │
                              │                         │
                              │    ┌─────────────────┐  │
                              │    │ Claude Code CLI │  │
                              │    │ + bash shell    │  │
                              │    └─────────────────┘  │
                              └─────────────────────────┘
```

---

## 🔗 References

- [ttyd - Share your terminal over the web](https://github.com/tsl0922/ttyd)
- [react-accessible-treeview](https://www.npmjs.com/package/react-accessible-treeview)
- [react-file-icon](https://www.npmjs.com/package/react-file-icon)
- [react-resizable-panels](https://www.npmjs.com/package/react-resizable-panels)
- [@uiw/react-codemirror](https://www.npmjs.com/package/@uiw/react-codemirror)
- [react-pdf](https://www.npmjs.com/package/react-pdf)
- [chokidar - File watcher](https://www.npmjs.com/package/chokidar)
- [docker-api gem](https://github.com/swipely/docker-api)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
