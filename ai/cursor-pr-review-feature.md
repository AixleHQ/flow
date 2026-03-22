# Feature: PR Review via Cursor Working Changes

## Research into the Cursor storage format

### Storage
- **File**: `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (SQLite, ~4 GB)
- **Table**: `cursorDiskKV` — key-value, values in JSON (blob)

### Key entities

#### 1. `composerData:<conversationId>` — conversation metadata
```json
{
  "_v": 9,
  "composerId": "<uuid>",
  "status": "completed" | "aborted",
  "richText": "<user prompt>",
  "fullConversationHeadersOnly": [
    { "bubbleId": "<uuid>", "type": 1 },  // type 1 = user message
    { "bubbleId": "<uuid>", "type": 2, "serverBubbleId": "<uuid>" }  // type 2 = assistant
  ],
  "codeBlockData": {
    "<file_uri>": {
      "<codeblockId>": {
        "_v": 3,
        "bubbleId": "<uuid>",
        "codeBlockIdx": 0,
        "codeblockId": "<uuid>",
        "status": "accepted" | "rejected" | "pending",
        "languageId": "typescriptreact",
        "diffId": "<uuid>",
        "lastDiffId": "<uuid>",
        "createdAt": 1755957794455,
        "lastAppliedAt": 1755957802522,
        "codeBlockDisplayPreference": "collapsed",
        "uri": { "$mid": 1, "fsPath": "...", "scheme": "file", "path": "...", "external": "file://..." }
      }
    }
  },
  "context": { ... },
  "conversationMap": {}
}
```

#### 2. `bubbleId:<conversationId>:<bubbleId>` — each message
```json
{
  "_v": 3,
  "type": 2,
  "bubbleId": "<uuid>",
  "isAgentic": true,
  "codeBlocks": [
    {
      "uri": { "scheme": "file", "path": "...", "_formatted": "file:///...", "_fsPath": "..." },
      "codeblockId": "<uuid>",
      "codeBlockIdx": 0,
      "content": "<full new file content>"
    }
  ],
  "checkpointId": "<uuid>",   // ← reference to the checkpoint made BEFORE the edit
  "capabilityType": 15,
  "toolFormerData": {
    "tool": 38,               // 38 = file edit tool
    "status": "completed",
    "rawArgs": "..."
  },
  "thinking": { "text": "...", "signature": "..." }
}
```

#### 3. `checkpointId:<conversationId>:<checkpointId>` — snapshot of the state BEFORE the edit
```json
{
  "files": [
    {
      "uri": { "$mid": 1, "external": "file:///...", "path": "/...", "scheme": "file" },
      "originalModelDiffWrtV0": [
        {
          "original": { "startLineNumber": 4, "endLineNumberExclusive": 5 },
          "modified": ["import React, { useState, useEffect } from 'react';"]
        }
      ]
    }
  ],
  "nonExistentFiles": [],
  "newlyCreatedFolders": [],
  "activeInlineDiffs": [...],
  "inlineDiffNewlyCreatedResources": { "files": [], "folders": [] }
}
```

#### 4. `codeBlockDiff:<conversationId>:<diffId>` — data for rendering the diff
```json
{
  "newModelDiffWrtV0": [
    {
      "original": { "startLineNumber": 2, "endLineNumberExclusive": 3 },
      "modified": ["import React, { useState, useEffect } from 'react';"]
    },
    {
      "original": { "startLineNumber": 66, "endLineNumberExclusive": 66 },
      "modified": ["", "  const tabLabelToHash = ...", "  };", ...]
    }
  ],
  "originalModelDiffWrtV0": []
}
```

### Relationships between entities

```
composerData (conversation)
  ├─ fullConversationHeadersOnly → [bubbleId references]
  ├─ codeBlockData → { fileUri: { codeblockId: { diffId, status } } }
  │
  └─ bubbleId (message)
       ├─ codeBlocks → [{ uri, content (full new file content) }]
       ├─ checkpointId → reference to the checkpoint (state BEFORE the edit)
       └─ toolFormerData → tool metadata
  │
  ├─ checkpointId (snapshot) → files + diffs relative to V0
  └─ codeBlockDiff (diff data) → newModelDiffWrtV0, originalModelDiffWrtV0
```

### Diff format

The diff is stored as a list of "hunks":
- `original.startLineNumber` — start line (1-based)
- `original.endLineNumberExclusive` — end line (exclusive, 1-based)
- `modified` — array of lines that replace the original range

If `startLineNumber == endLineNumberExclusive`, this is an insert after the specified line.

### URI format

```json
{
  "$mid": 1,
  "scheme": "file",
  "authority": "",
  "path": "/absolute/path/to/file",
  "query": "",
  "fragment": "",
  "_formatted": "file:///absolute/path/to/file",
  "_fsPath": "/absolute/path/to/file"
}
```

## Available mechanisms

### Deep Links
- `cursor://` URI scheme is registered in macOS
- Cursor supports deep links: `cursor://anysphere.cursor-deeplink/<type>?<params>`
- Types: `prompt`, `command`, `rule`, `mcp/install`
- There is **NO** deep link for "apply changes" or "trigger agent"
- Web fallback: `https://cursor.com/link/...`

### Extension URI Handler
- VS Code extensions can register URI handlers via `vscode.window.registerUriHandler()`
- In Cursor, `vscode.env.uriScheme` returns `"cursor"`
- An extension with ID `my.pr-review` will handle `cursor://my.pr-review/open?pr=123`
- This is a **bridge** between the browser extension and the Cursor extension

### SQLite from the extension
- `sql.js` (WASM) — works without native dependencies, portable
- `better-sqlite3` — fast, but requires `electron-rebuild` on every Cursor update
- MCP server — runs as a separate process, can use `better-sqlite3` without issues

## Solution architecture

### Components

```
┌─────────────────┐     cursor://my.pr-review/open?pr=URL    ┌──────────────────┐
│  Browser Ext.   │ ──────────────────────────────────────▶   │  Cursor Extension│
│  (Chrome/FF)    │                                           │  (VS Code ext)   │
│                 │                                           │                  │
│ "Review          │                                           │ 1. URI Handler   │
│ in Cursor" button│                                           │ 2. gh pr checkout│
│ on GitHub PR page│                                           │ 3. Writes to DB  │
└─────────────────┘                                           │ 4. Reload window │
                                                              └──────────────────┘
                                                                      │
                                                                      ▼
                                                              ┌──────────────────┐
                                                              │   state.vscdb    │
                                                              │  (SQLite)        │
                                                              │                  │
                                                              │ composerData     │
                                                              │ bubbleId         │
                                                              │ checkpointId     │
                                                              │ codeBlockDiff    │
                                                              └──────────────────┘
```

### Flow

1. **Browser Extension** adds a "Review in Cursor" button to the GitHub PR page
2. On click it opens `cursor://my.pr-review/open?repo=owner/repo&pr=123`
3. **Cursor Extension** intercepts the URI via `registerUriHandler`
4. Extension:
   a. Checks for uncommitted changes → asks to stash/discard
   b. `gh pr checkout 123` — switches to the PR branch
   c. Gets the diff: `gh pr diff 123` + base/head files
   d. Converts unified diff → Cursor hunk format
   e. Writes to state.vscdb (via sql.js or child_process with sqlite3)
   f. Calls `vscode.commands.executeCommand('workbench.action.reloadWindow')`
5. Cursor reloads → sees pending changes → shows the "Accept/Reject" UI

### Alternative approach: Command Palette (without a browser extension)

The Cursor Extension registers a command in the Command Palette:
- `PR Review: Open PR` → enter PR URL → the same flow (steps 4a-4f)
- Does not require a browser extension at all
- Can be invoked from the agent: "open PR #123 for review"

## Implementation plan

### Phase 1: Cursor Extension (MVP)

**Scope**: Command Palette command, without a browser extension

```
cursor-pr-review/
├── package.json          # Extension manifest
├── src/
│   ├── extension.ts      # Activation, commands, URI handler
│   ├── github.ts         # gh CLI wrapper (pr diff, checkout, file contents)
│   ├── diffConverter.ts  # Unified diff → Cursor hunk format
│   ├── dbWriter.ts       # SQLite writer (composerData, bubbleId, checkpoint, codeBlockDiff)
│   └── gitOps.ts         # Stash/checkout/branch operations
├── wasm/
│   └── sql-wasm.wasm     # sql.js WASM binary
└── tsconfig.json
```

**Steps:**
1. Scaffold a VS Code extension with `yo code`
2. Implement `github.ts` — fetching PR data via the `gh` CLI
3. Implement `diffConverter.ts` — parsing unified diff, generating Cursor hunks
4. Implement `dbWriter.ts` — writing to state.vscdb via sql.js
5. Implement `gitOps.ts` — stash, checkout
6. Wire everything together in `extension.ts` — command + URI handler
7. Testing on a real PR

### Phase 2: Browser Extension

**Scope**: Chrome extension, button on the GitHub PR

```
cursor-pr-review-browser/
├── manifest.json         # Chrome MV3 manifest
├── content.js            # Inject "Review in Cursor" button
└── icons/
```

**Logic**: content script finds the PR URL → builds a `cursor://` deep link → `window.location.href`

### Phase 3: Polish

- Firefox support
- Handling large PRs (>50 files)
- Handling binary files (skip)
- Handling new/deleted files
- Extension settings (auto-stash, target workspace path)
- Publishing to the Cursor Marketplace + Chrome Web Store
