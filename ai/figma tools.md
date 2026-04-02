# Executive Summary  
Figma now offers two official MCP (Model Context Protocol) servers – a **remote HTTP server** (at `https://mcp.figma.com/mcp`) and a **desktop WebSocket server** embedded in the Figma app – that let LLM agents *read* design context and even *capture live UIs* into Figma.  The remote server (authenticated via OAuth or personal tokens) works in the cloud/browser, while the desktop server (via Dev Mode) requires the Figma desktop app.  In addition, the community has built **“bridge” architectures** using a local Node.js or Electron app + a custom Figma plugin. These run a local MCP server (stdio-based or container) that communicates over WebSocket to a plugin inside Figma. Such bridges (e.g. *Figma Console MCP*, *Cursor Talk-to-Figma*, *TalkToFigma*, *Figma-MCP-Bridge*, etc.) provide **full read-write access** to Figma documents: agents can create frames/shapes/components, read/write variables/styles, export assets, etc.  By contrast, a pure **REST/token-based** approach (Figma’s official REST API) can only *read* file contents/images (with strict rate limits) and cannot programmatically create or edit designs.  **Browser automation** or “UI-to-Figma” tools (e.g. Puppeteer or Claude Code’s capture flow) can convert rendered HTML/CSS to Figma frames, but these are bespoke pipelines rather than public APIs.  The AI-native design app **Paper** follows a similar pattern: a local MCP server in Paper’s desktop app, which can sync Figma context (read-only) into Paper, and vice versa with full write access.

For running agents in the cloud, the only viable path is using Figma’s token-based APIs (REST or remote MCP) for *reading/analyzing* designs.  **Design creation in Figma still requires a live Figma context** (desktop or web) or a bridging plugin.  A hybrid pattern is therefore needed: agents output a design AST or a set of commands, which are then *applied* to Figma by an external runner (e.g. a CLI or plugin).  For example, an agent might produce a JSON AST of the UI; a light server or plugin then reads that AST and uses the Figma plugin API to construct frames/nodes.  Below we compare all approaches, list their components, capabilities and limitations, and sketch implementation patterns (with Mermaid diagrams and code snippets). We conclude with security/auth notes and recommended architecture for Aixle (cloud agents to **editable** Figma output), noting that truly cloud-only design-to-Figma is blocked by Figma’s architecture.

**Recommendations:** For Aixle, use Figma’s **remote MCP** or **REST API** in cloud for *analysis* and planning. For *creation*, embed a lightweight bridge on the user’s side (or have Aixle trigger a user-approved session) so that generated designs can be injected. In practice, the most complete solution today is to run an MCP-bridge locally (or in a container mapped to the user’s Figma) and have the cloud agent send design commands to it. This avoids manual transcription and ensures editable Figma output. We outline migration steps from cloud-only prototypes to this hybrid model below.

## Architectures and Data Flows  

We categorize integration patterns into (1) **Official MCP servers**, (2) **Plugin-bridge MCP servers**, (3) **Desktop bridging apps**, (4) **Token/REST-based**, (5) **Browser automation**, and (6) **Paper.desktop**. Each has a distinct data flow:

- **Official MCP server (Remote):** Agentic tools (e.g. Claude Code, VS Code) talk over HTTPS to Figma’s cloud MCP endpoint (`mcp.figma.com/mcp`)【17†L119-L127】【25†L78-L87】. Figma authorizes via OAuth or PAT and returns design context or captures UI into Figma. No local Figma process is needed – the Figma file can be in the web browser. This flow is essentially *server-to-server*.

- **Official MCP server (Desktop):** Figma’s Dev Mode can “turn on” a local MCP server in the desktop app (shown in Dev Mode sidebar)【18†L139-L148】. A client (VS Code, etc.) connects via WebSocket to the URL provided (e.g. `ws://localhost:...`). The agent’s tools communicate over this socket to read/write the open Figma file. 

- **Plugin-bridge MCP (Node/WebSocket):** A **local Node (or Bun) process** implements an MCP server (stdio or HTTP). It launches a WebSocket server on `localhost` and a lightweight **Figma plugin** (installed in the user’s desktop Figma) connects as a WebSocket client. The plugin exposes the Figma Plugin API; incoming WebSocket messages carry tool calls from the agent, and outgoing messages carry responses or events. This enables bidirectional, real-time control of Figma from any MCP client.  
  ```mermaid
  graph LR
    Agent["AI Agent / LLM (Cli/Cursor/VSC)"]
    MCPServer["Local MCP Server (Node.js)"]
    WebSocket["WebSocket (e.g. ws://localhost:3055)"]
    FigmaPlugin["Figma Plugin (desktop)"]
    FigmaDoc["Figma File / Canvas"]
    Agent -- stdio/HTTP --> MCPServer
    MCPServer -- WebSocket --> FigmaPlugin
    FigmaPlugin -- Figma API --> FigmaDoc
    MCPServer --<<response>>--> Agent
  ```
  *(Example: Southleft’s [figma-console-mcp](https://github.com/southleft/figma-console-mcp), Magic-Spells [figma-mcp-bridge](https://github.com/magic-spells/figma-mcp-bridge), Figmind, Firas’s Figma-MCP-Write-Bridge, and the Alpha “cursor-talk-to-figma” use this pattern.)*

- **Desktop Bridge App (Electron):** An Electron or Node desktop app (e.g. *TalkToFigmaDesktop*) bundles the WebSocket MCP server with a GUI/tray. It may spawn per-client stdio servers and routes them via a central WebSocket (typically on port 3055) to the plugin. This simplifies installation (no manual NPX). The flow is similar to above, but the MCP server processes are managed by the app.  
  ```mermaid
  graph LR
    Agent["AI Clients"]
    StdioSrv["stdio MCP Servers (spawned)"]
    ElectronApp["Desktop App (Electron)"]
    WebSocket["WebSocket Server (3055)"]
    FigmaPlugin["Figma Plugin"]
    Agent --> StdioSrv
    StdioSrv --> ElectronApp
    ElectronApp --> WebSocket
    WebSocket --> FigmaPlugin
    FigmaPlugin --> FigmaDoc
  ```
  *(Example: [TalkToFigmaDesktop](https://github.com/grab/TalkToFigmaDesktop) and [cursor-talk-to-figma-mcp](https://github.com/grab/cursor-talk-to-figma-mcp) are variants of this.)*

- **Figma REST API (Token):** The agent (in cloud) uses Figma’s public REST endpoints (via HTTPS) with a Figma personal access token. It can **read** file structure, component data, export images, etc. Data flow:  
  ```mermaid
  graph LR
    Agent["AI Agent (server)"]
    FigmaAPI["Figma REST API (GraphQL)"]
    FigmaBackend["Figma Cloud Data"]
    Agent -- HTTPS+Token --> FigmaAPI
    FigmaAPI -- read-only data --> Agent
  ```
  Crucially, Figma’s REST API supports **file_content:read**, images, comments, etc. with a token【35†L83-L91】, but it **cannot create or modify** design nodes or frames. *All operations are constrained to existing file data.*  

- **Headless/Browser Capture:** The agent runs a headless browser (Playwright/Puppeteer) on some live UI and uses a capture tool (e.g. [Claude Code to Figma](https://www.figma.com/blog/introducing-claude-code-to-figma/) flow). The data flow is ad hoc: Browser UI → **DOM/CSS AST** → conversion script → Figma (via user-invoked capture or plugin). For example, Claude Code’s feature “capture UI to Figma” leads the developer through an interactive capture toolbar and then pastes an editable frame into Figma【28†L278-L287】. In practice, open-source implementations of this are rare; one could custom-scrape DOM and build Figma API calls, but no standardized library exists. The end result *becomes* a Figma frame, but only if a user takes manual steps (e.g. clicking capture in browser and then following a link)【28†L278-L287】.

- **Paper.design Desktop (MCP):** Paper (an AI-native design app) embeds its own MCP server at `http://127.0.0.1:29979/mcp`【7†L81-L90】. Agents connect Paper’s server (for full read/write in Paper) and can also connect Figma’s server simultaneously【7†L167-L175】. Paper’s MCP is local to the Paper app, similar to Figma’s desktop MCP. The key point: **Paper’s MCP can read Figma via the official Figma MCP (read-only)** and write to Paper. So Paper can import style/token info from Figma, but cannot feed designs back into Figma other than as images. (Paper’s workflow: “Figma MCP server is read only… Paper MCP can read and write”【7†L175-L183】.)

The following **Mermaid diagram** summarizes the main MCP flows (official and plugin-bridge):

```mermaid
graph TD
    subgraph Figma Remote MCP
      A1[Agent (Claude/VSCode)] -- HTTP/OAuth --> FigmaRemoteMCP
      FigmaRemoteMCP --> FigmaCloudData
    end
    subgraph Local Plugin Bridge
      A2[Agent (Claude/Cursor)] -- stdio --> MCPServer(Node)
      MCPServer -- WS --> FigmaPlugin(Plugin in Figma)
      FigmaPlugin --> FigmaFile(Figma Document)
    end
    subgraph Desktop Bridge App
      A3[Agent Tools] --> StdioServers[Multiple stdio servers]
      StdioServers --> ElectronApp
      ElectronApp --> WSLocal(WebSocket 3055)
      WSLocal --> FigmaPlugin
      FigmaPlugin --> FigmaFile
    end
    subgraph REST API
      A4[Agent (Cloud)] -- HTTPS+Token --> FigmaRESTAPI
      FigmaRESTAPI --> FigmaCloudData
    end
    style FigmaRemoteMCP fill:#f9f,stroke:#333,stroke-width:1px
    style MCPServer fill:#ccf,stroke:#333,stroke-width:1px
    style FigmaRESTAPI fill:#fcc,stroke:#333,stroke-width:1px
```

## Capabilities, Components, and Limitations  

Below we compare each approach in terms of required components, capabilities (what it can read/write), limitations, typical tools, and example implementations. Key capabilities include: *Read design nodes/data*, *Write or create nodes*, *Edit layout*, *Export images/assets*, *Access styles/variables/components*. 

### 1. Official Figma MCP Server (Remote HTTP)  
- **Components:** Figma account (any plan), Figma file (in browser or desktop), an MCP-compatible client (Claude Code, VS Code, Cursor, etc.) configured to use `https://mcp.figma.com/mcp`. No Figma desktop required; uses OAuth or PAT authentication【25†L99-L108】.  
- **Capabilities:** Read design context (layers, components, styles, variables), extract code from selected frames, and **capture live UI** into Figma (for supported clients). Specifically: agents can “generate designs from the live UI” of a web app and have the MCP client create new frames in Figma【25†L78-L87】【28†L278-L287】. They can also pull design tokens (colors, text styles, etc.) via MCP tools (Table of tools is in Figma’s Dev Docs). However, this write capability is tied to the capture workflow and currently limited to certain clients (Claude, VS Code, Codex)【28†L276-L284】. The remote server’s “tools” include commands like `capture_ui`, `get_design_context`, and `create_code_from_selection`.  
- **Limitations:** Requires user sign-in (OAuth) and Dev Mode enabled. Not user-controllable like a plugin – the flow is conversational (agent must prompt, then follow interactive steps【28†L278-L287】). It is **mostly read-only** except for the guided capture tool. It cannot arbitrarily add or modify existing Figma nodes on command (only create new frames from captured UI). Also, only supported in a few MCP clients. There’s no automatic local synchronization – the capture step is a manual browser tool.  
- **Typical Tools/Libraries:** Figma’s built-in MCP server (no external code needed), plus client apps (VSCode Figma extension, Claude Code plugin, etc.). The agent-side uses `@modelcontextprotocol` SDK and HTTP transport.  
- **Example:** Official only; no community code (the server is proprietary). Setup is documented in Figma’s Dev Docs【25†L99-L108】.  

### 2. Official Figma MCP Server (Desktop)  
- **Components:** Figma Desktop App (Dev seat or Full seat), a design file open in Dev Mode. When Dev Mode is enabled, there’s an MCP server URL (ws:// or http:// on localhost)【18†L139-L148】. An MCP client (e.g. VS Code, Claude) is configured to that URL.  
- **Capabilities:** Same *tools* as the remote server (design context extraction, code generation from frames, etc.), but now running locally. Figma notes you can “keep your design system consistent” and “extract variables, components, layout data” into your IDE【1†L190-L199】. Because it’s local, it may have fewer rate limits and immediate updates. However, like the remote server, the official desktop MCP is mainly **read-only** in terms of design manipulation – it pulls data for the agent. In Figma’s docs, it’s implied that custom tools (like capturing live UI) may not be available on the desktop MCP without going through the same capture toolbar.  
- **Limitations:** Requires local Figma (cannot be used if Figma isn’t installed or open). Still not a programmable API – it’s limited to Figma’s pre-defined MCP tools. (Figma even says “the official Figma MCP server has only read-only tools. You cannot change anything using it”【30†L260-L268】.)  
- **Tools:** The built-in desktop MCP; clients like VSCode, Cursor connect via config (e.g. copy the URL from Figma Dev Mode)【18†L139-L148】.  
- **Example:** Official Figma feature; see Figma Dev Docs instructions【18†L139-L148】【25†L99-L108】.  

### 3. Plugin-Bridge MCP (Local Node + WebSocket)  
- **Components:** Figma Desktop App (any seat), a **custom Figma Plugin** (installed via “Import Plugin from manifest”) that opens a WebSocket to localhost. A local Node (or Bun) MCP server process (often started via `npx` or CLI) that implements MCP tools and listens on stdio or an HTTP/MCP endpoint.  
- **Capabilities:** **Full read/write access.** These bridges expose a large set of Figma operations (“62+ tools”【9†L264-L272】, “57+ tools”【11†L25-L30】) covering: creating shapes (frames, rectangles, text, etc.), applying styles/variables, layout/autolayout, grouping/ungrouping, boolean operations, component instantiation, exporting assets (PNG/SVG), reading and updating design tokens, taking screenshots, etc. For example, Southleft’s Console MCP supports design *creation* (via `figma_execute`), variable CRUD, mode management, and “Reliable component descriptions”【12†L882-L891】. Magic-Spells’s bridge explicitly lists “Create shapes, modify styles, manage components, export assets”【9†L264-L272】. In effect, any action the Figma Plugin API allows can be proxied. Changes are applied *live* in the open Figma file; agents see results instantly in Figma.  
- **Limitations:** Requires Figma Desktop (web Figma cannot host local plugins) and the plugin must be running in the file. The plugin window/iframe must stay open (or persistent) during the session. If the Figma file is closed or the plugin stops, the connection breaks. Also, these solutions only work on machines where Figma desktop is available (so not purely cloud). Communication is local WebSocket, so networked/distributed setups need port forwarding (ENV `FIGMA_WS_HOST = 0.0.0.0` to expose outside container)【12†L909-L918】. Multi-file support often requires one plugin instance per file; some servers auto-index by file key【12†L905-L914】.  
- **Typical Tools/Libraries:** Node.js or Bun; [@modelcontextprotocol/sdk](https://www.npmjs.com/package/@modelcontextprotocol/sdk) for MCP server; `ws` or `socket.io` for WebSocket; the Figma Plugin API (TypeScript/JavaScript). Many use NPX for quick start (e.g. `npx @magic-spells/figma-mcp-bridge`).  
- **Example Repos:** 
  - **Southleft/figma-console-mcp** (TypeScript, 923★) – a mature implementation with NPX deployment【38†L1-L4】. Key files: `figma-desktop-bridge/manifest.json`, `src/index.ts`, `src/api-tools.ts`.  
  - **grab/cursor-talk-to-figma-mcp** (TypeScript, 6.5k★) – Cursor-focused with Bun; files: `src/talk_to_figma_mcp/server.ts`, `src/cursor_mcp_plugin/manifest.json`【32†L297-L305】【43†L39-L46】.  
  - **Magic-Spells/figma-mcp-bridge** (JavaScript, 31★) – Claude CLI integration; key: `src/index.js`, `plugin/manifest.json`【9†L264-L272】.  
  - **firasmj/Figma-MCP-Write-Bridge** (TypeScript, 4★) – similar bridge; main code in `figma-write-bridge.ts`, `server.ts`【13†L282-L290】.  
  - **guhcostan/figmind** (TypeScript, 0★) – MCP server with Cursor plugin; key: `src/talk_to_figma_mcp/server.ts`, `packages/figma-plugin/manifest.json`.  
  - **Antonytm/figma-mcp-server** (TypeScript, 120★) – early bridge; key: `mcp/server.ts`, `plugin/manifest.json`【30†L354-L363】.  
  - Each of these includes instructions to run an MCP server and import a Figma plugin. They advertise “real-time bidirectional communication”【9†L264-L272】 and often auto-scan ports (e.g. 9223–9232) for connections【12†L898-L907】.  

### 4. Desktop Bridge Apps (Electron)  
- **Components:** Figma Desktop App; an installed desktop application (e.g. Electron) that packages the WebSocket server and optionally hosts a tray UI. The app automatically spawns MCP servers for each agent client, managing the stdio processes. A companion Figma plugin (usually the same as above) connects to the app’s WS.  
- **Capabilities:** Essentially identical to the plugin-bridge above (full read/write). The difference is ease of install and multi-client support. The TalkToFigma app, for instance, supports multiple MCP clients and shows status in system tray【15†L360-L368】. Agents see one WebSocket server (3055) which multiplexes to the plugin【15†L461-L470】.  
- **Limitations:** Still requires Figma desktop. Adds an extra layer (Electron) which may impose OS trust hurdles (e.g. macOS Gatekeeper)【15†L381-L390】. But it can run as a background service and auto-start the server.  
- **Tools:** Electron (for UI), Node.js, Bun or Node for backend, WebSocket libraries.  
- **Example Repos:** 
  - **grab/TalkToFigmaDesktop** (TypeScript/Electron, 26★) – provides a tray app; key: `src/main.ts`, `src/socket.ts`, plugin `manifest.json`【15†L509-L518】. 
  - **grab/cursor-talk-to-figma-mcp** (above) also includes a desktop setup via Bun.  
  - These projects often auto-install the MCP server binary and handle Windows/macOS packaging.  

### 5. Figma REST API (Token-based)  
- **Components:** Any server or container running code with access to the internet. A **Figma Personal Access Token (PAT)** or OAuth app credentials. The token must have scopes like `file_content:read` and `file_read` to fetch designs【35†L83-L91】. The agent calls Figma’s REST (GraphQL) endpoints over HTTPS (e.g. `/files/{file_key}`, `/images`, etc.).  
- **Capabilities:** *Read-only.* The API can retrieve file metadata, the full document tree, component descriptions, comment threads, image fills as PNGs, and export frame images. It can also enumerate components, styles, and (with Enterprise) variables【35†L83-L91】. Essentially any data needed to understand an existing design is accessible. Rate limits apply (e.g. ~10–100 requests/min for Full seats【37†L128-L135】), so heavy usage may be throttled.  
- **Limitations:** **No design creation or editing.** There is no endpoint to create new frames, modify node properties, or upload new nodes. Thus an agent *cannot* generate an editable design via REST alone. (It could only, at best, craft a JSON that a human or plugin must import.) Any attempt to write would require scraping the UI or using a user-side plugin. Also, the PAT model means you operate under *your account’s* rate limits (requests from different apps share one budget)【37†L108-L117】.  
- **Typical Tools/Libraries:** Standard HTTP/GraphQL tools. Figma provides client libraries in JS/Python, and many third-party wrappers (e.g. [node-figma](https://github.com/mikbry/figma-js)).  
- **Example Repos:** Pure API usage is found in thousands of projects, but notable CLI tools include [figma-export](https://github.com/figma-extract/figma-export) (focus on design tokens, not full design creation). No open-source can “write designs” via REST because it’s impossible.  

### 6. Headless/Browser Automation (DOM → Figma)  
- **Components:** Agent-controlled browser (e.g. Puppeteer/Playwright). Possibly an intermediate “UI-to-AST” converter script. A Figma integration on the user side (like a plugin or official devtool) to import the result.  
- **Capabilities:** Agent “captures” a running UI (including HTML/CSS, screenshots). It parses the DOM to generate a semantic layout (e.g. box model, text content, images). This is then *translated* into Figma nodes (frames, text nodes, images) either by generating a Figma plugin payload or by using an MCP “capture” tool. Claude Code’s example uses an interactive capture toolbar and then pastes Figma frames【28†L278-L287】. In theory, one could automate this: e.g. agent asks to capture UI, the client opens a browser window and triggers the capture.  
- **Limitations:** There’s no turnkey library; accuracy depends on the converter. Complex dynamic content (animations, webgl) won’t fully translate. Usually requires a user to confirm capture actions. The output is editable in Figma (frames with auto-layout), but achieving pixel-perfect fidelity is hard.  
- **Tools:** Puppeteer, jQuery DOM extraction, CSS parsers. Possibly cognitive frameworks (LLMs that interpret HTML).  
- **Examples:** No standard open-source; the closest is Figma’s own feature (“Capture UI” in supported MCP clients). A blog demo by Figma shows capturing code output to Figma frames (no public code).  

### 7. Paper.design (Desktop)  
- **Components:** Paper desktop app. Paper’s MCP server runs on `localhost:29979`【7†L81-L90】. Agents (in Cursor, Claude, etc.) can add `paper` as a custom MCP pointing to `http://127.0.0.1:29979/mcp`【7†L76-L85】. In Figma’s case, you also enable Figma’s MCP in the same IDE/CLI, so both contexts (Paper file and Figma file) are accessible【7†L167-L175】.  
- **Capabilities:** Paper can *read* Figma’s open file context (via Figma MCP) and use it to inform design creation in Paper. E.g. agents can “create a design system in Paper matching the Figma file”【7†L167-L175】. Within Paper, all standard design operations (create frames, layouts, styles) are possible (Paper is itself a design tool). Crucially, Paper’s MCP server is **read/write** for Paper documents, but only read Figma. So agents can move assets from Figma into Paper but not vice versa, except via manual export.  
- **Limitations:** Not directly editing Figma. The flow is: use Figma as inspiration, build in Paper. To affect Figma files, one would have to re-export from Paper (as image or copy/paste vectors – none built-in).  
- **Example:** Paper’s docs and blog (no public repo).  

## Running Agents Purely in the Cloud (Token-only)  

No solution today can run an LLM agent in the cloud that *fully* writes a Figma design using only a Figma token. The Figma API (PAT or OAuth) is strictly read-only regarding design nodes. **Technical blockers:**  

- *No write APIs:* Figma has no endpoint to create shapes or frames. Any attempt to generate design must rely on the official MCP (desktop) or on a plugin, both of which require a live Figma session.  
- *Authentication:* Even with a PAT, only REST endpoints (file fetches, image exports) are allowed【35†L83-L91】. The remote MCP (for capture) uses OAuth and interactive consent – not automatable in a headless cloud.  
- *No headless Figma:* Figma’s desktop app does not run on a server (no headless mode), and their web app is not scriptable to the level of injecting nodes.  

**Workarounds:** The only partial routes are “human-in-the-loop”: an agent generates an intermediate (e.g. design spec, AST, or HTML/CSS), then a user or a local service uses that to populate Figma. For example, an agent could output JSON describing a UI; a separate script (running on a machine with Figma desktop) could consume it via the plugin API. Or an agent can instruct a user to run the official capture tool: e.g. “/mcp, start capture UI, go to URL X…” – but this still requires an interactive user.  

In summary, **pure cloud** agents can *analyze* and *propose* designs but cannot *place* them in Figma without a Figma client. The only feasible cloud-only flows are:
- **Read/analysis** (Figma REST/MCP remote): agent reads file content, audits design tokens, extracts images, etc.  
- **Design generation out-of-band:** agent produces code or AST (e.g. HTML/CSS or an intermediate JSON). That artifact could be stored or sent back to a human/developer, who then uses a local tool to materialize it.  
- The new Figma blog suggests a future where you “capture code into Figma”【20†L122-L131】, but this still involves the developer pasting or pushing content into the Figma canvas.  

No public library or MCP app exists to “upload design via API” as of 2026. Attempts like automating dev-mode via Puppeteer face the same limitation: without a human granting permissions, they can’t control the local MCP. 

## Implementation Patterns  

Below are two illustrative patterns (with pseudocode) for how a cloud agent could *produce* editable Figma content via a bridge:

1. **AST → Figma via Plugin Bridge.**  
   - *Server (cloud agent):* The agent runs in the cloud and outputs a design AST (e.g. JSON describing frames and nodes) or a sequence of MCP tool calls (e.g. “create_frame”, “create_text”, etc.). It then invokes an MCP Server library to send these tool calls to the Figma plugin (over WebSocket) as an MCP tool invocation.  
     
     ```javascript
     // Simplified: Agent-side Node MCP server (stdio transport)
     const { MCPServer } = require('@modelcontextprotocol/sdk');
     const { WebSocketTransport } = require('@modelcontextprotocol/transport-ws');
     const wss = new WebSocketServer({ port: 3055 }); // as in figma-mcp-bridge
     const tools = [
       { name: 'create_frame', args: [
           { name: 'name', type: 'string' },
           { name: 'width', type: 'number' },
           { name: 'height', type: 'number' }
         ]
       },
       // ... other tool specs ...
     ];
     const mcp = new MCPServer({
       transport: WebSocketTransport({ server: wss }), 
       tools
     });
     // Define tool implementation by forwarding to plugin:
     mcp.addTool('create_frame', async ({ args, respond }) => {
       const msg = JSON.stringify({ tool: 'create_frame', args });
       // Send to all connected plugin clients
       wss.clients.forEach(client => client.send(msg));
       // Wait for plugin to respond with new frame ID
       const result = await mcp.waitForResponse('create_frame');
       respond({ frameId: result.id });
     });
     ```
     
   - *Figma Plugin:* The plugin (running in Figma) listens on the WebSocket. On receiving a message like `{"tool":"create_frame","args":{"name":"Hero","width":800,"height":600}}`, it uses the Figma Plugin API to execute it. Then it sends back a response.
     ```js
     // In plugin code (main thread)
     const socket = new WebSocket('ws://localhost:3055');
     socket.addEventListener('message', event => {
       const msg = JSON.parse(event.data);
       if (msg.tool === 'create_frame') {
         const { name, width, height } = msg.args;
         const frame = figma.createFrame();
         frame.name = name;
         frame.resize(width, height);
         figma.currentPage.appendChild(frame);
         socket.send(JSON.stringify({
           tool: 'create_frame_response',
           id: frame.id
         }));
       }
       // ... handle other tools ...
     });
     ```
     The plugin must call `figma.showUI()` (even a 1×1 px dummy) or persist headless. The code above merges the plugin’s main thread and UI thread for brevity; in practice, you may use `figma.ui.onmessage`.  

2. **DOM/CSS → Figma via Capture Flow.**  
   - *Agent Workflow:* Agent tells the MCP client to open a browser and capture UI. E.g.: `agent.send("/mcp: capture_my_app_to_figma at http://localhost:3000")`. The client follows instructions, capturing HTML/CSS of the page. It then converts it into an HTML/CSS tree.  
   - *Conversion:* The client uses a conversion algorithm (possibly using Figma’s own [point-to-node clustering, text detection, layout inference](https://www.figma.com/blog/introducing-claude-code-to-figma/)). The outcome is a node tree. The client then invokes Figma’s UI to paste or create that tree in a new frame (behind the scenes, it likely calls similar plugin tools as above).  
   - *Server-Side Snippet:* (Pseudo)  
     ```python
     # Agent instructs client:
     agent_response = agent.query("Start local server at port 9999 and capture UI from /login screen to a new Figma file")
     # Client opens http://localhost:9999/login in a headless browser, takes DOM snapshot.
     dom_tree = browser.capture_dom()
     # Build Figma commands:
     commands = convert_dom_to_figma_commands(dom_tree)  # user-defined mapping
     # Send commands via MCP or plugin API
     for cmd in commands:
         send_to_figma_plugin(cmd)  # similar to pattern above
     ```
   - In practice, the actual “convert_dom_to_figma_commands” is complex (requires layout analysis, auto-layout decisions, etc.). This pattern is essentially how “UI capture” features work, though Figma currently only exposes them via the official MCP clients with manual steps【28†L278-L287】.  

These patterns illustrate the general idea: *the agent never writes to Figma directly*. Instead, it either uses official MCP tools (which use Figma’s back-end) or generates a payload that a local Figma-connected process executes. 

## Security, Auth, and Operational Notes  

- **Authentication:** Official MCP (remote) requires Figma OAuth or PAT authorization【25†L99-L108】. The agent’s MCP client must be logged in. For token-based REST, generate a **Personal Access Token** and set appropriate scopes (e.g. `file_content:read`, `file_read`)【35†L83-L91】. Store tokens securely (e.g. in environment variables); follow GitGuardian best practices for Figma tokens【34†L9-L12】.  
- **Token Scopes:** PATs can access most user data under allowed scopes. Figma scopes include `file_read`, `file_write` (but note: even with `file_write`, the API does not support design edits), `comment_write`, etc. If Figma ever adds design-write scopes, watch for updates.  
- **Rate Limits:** Figma enforces per-user and per-app rate limits【37†L128-L135】. For Full seats: roughly 10–100 calls/minute depending on endpoint tier. A cloud agent using one PAT counts as a single user; heavy use (e.g. exporting hundreds of images) can hit 429 limits. Design for exponential backoff and caching. Note: REST API rate limits are per-API-key (PAT) across your app【37†L107-L116】, whereas MCP (local) traffic is not rate-limited by Figma (it’s real-time socket).  
- **MCP Security:** The local WebSocket (ports 9223–9232 or 3055) only listens on localhost by default. If running in Docker, set `FIGMA_WS_HOST=0.0.0.0` with care; otherwise the socket is not exposed externally【12†L909-L918】. Do not expose the MCP server to untrusted networks. These bridges inherently grant “full access” to your open Figma file, so only run MCP servers you trust. Figma’s official stance: “Plugin gives access to your design document for external systems… it works on local machine and does not expose any information to networks”【30†L374-L382】.  
- **Agent/Session State:** MCP tools are stateless RPC calls; if one command takes too long, some bridges will time out (Antonytm’s notes mention returning timeout if plugin doesn’t respond)【30†L364-L370】. Long-running design generation should chunk commands. Also, Figma plugins have a limited runtime (they may expire or crash if doing very heavy work). The agent session might need to re-initialize (restart MCP) if disconnected【7†L135-L143】.  
- **Permissions/UX:** Some clients prompt the user when calling an MCP tool. For example, Paper’s doc warns that Figma MCP is read-only (so you can allow “always”) but Paper’s MCP is read-write (grant on demand)【7†L175-L183】. Similarly, when a plugin bridge calls Figma API, Figma’s desktop may show a “External script is calling this plugin” banner. Users should confirm these if running interactive demos.  
- **Persistence:** Figma plugin state (in-memory or via `figma.clientStorage`) is lost when the plugin UI closes or Figma restarts. Some bridges keep the plugin UI open but hidden. Others re-instantiate on each connection. Agents should save intermediate AST in their own storage, not rely on plugin memory.  
- **Sandboxing:** Figma plugins run in a sandbox (no `eval`, limited JS APIs). But the plugin code we write can use all Figma API calls. The local MCP server usually runs as a Node process on the host OS, so it can do anything that Node can (even spawning processes). Beware of exposing any secret (like PAT) to the plugin side – keep tokens on the server side only.  

## Comparison Table of Approaches  

| Approach              | Components Needed                              | Capabilities (can do…)                                     | Limitations & Notes                                     | Example Projects (Open Source)                 |
|-----------------------|-----------------------------------------------|------------------------------------------------------------|---------------------------------------------------------|------------------------------------------------|
| **Figma MCP (Remote)**| Figma account, Dev Mode, AI client (CLI/IDE).<br>No local plugin or app.   | *Read*: full design context (nodes, layers, components, tokens)【25†L78-L87】;<br>*Write*: capture live UI into new Figma frames (via capture tool)【28†L278-L287】;<br>generate code from selected frame. | *Requires OAuth/PAT auth*【25†L99-L108】; only supported in select clients; write operations limited to guided capture; *no arbitrary edits*; interactive flow (agent must prompt to open capture toolbar)【28†L278-L287】. | Figma DevDocs (official)  |
| **Figma MCP (Desktop)**| Figma Desktop app (Dev seat), Dev Mode enabled, AI client.  | Same tools as Remote (design context, code from frames)【1†L190-L199】. <br>(*Note:* Still essentially read-only for nodes) | *Requires Figma desktop*; must have file open; only official tools; no custom tools beyond provided MCP. Official docs: “read-only tools, cannot change document”【30†L260-L268】. | Figma DevDocs (official)  |
| **Plugin-Bridge MCP**| Figma Desktop app, **bridge plugin** installed in Figma, local MCP server process (Node/Bun/TS) running (via npx or CLI), AI client.  | *Read* any node data, styles, selections; *Write/create*: frames, shapes, text, components, images, boolean ops; manage variables, auto-layout, etc.【9†L264-L272】【12†L882-L891】.  | Must run on same machine as Figma Desktop; plugin must be active. Only works in “Local Mode” (NPX/git) – not supported if the client is using a remote-only mode【12†L918-L920】. Plugin UI must stay open or work in background. Network: default localhost; in Docker set host to 0.0.0.0 if needed.【12†L909-L918】. | [southleft/figma-console-mcp](https://github.com/southleft/figma-console-mcp) (TS, 923★)【12†L882-L891】<br>[magic-spells/figma-mcp-bridge](https://github.com/magic-spells/figma-mcp-bridge) (JS, 31★)【9†L264-L272】<br>[firasmj/Figma-MCP-Write-Bridge](https://github.com/firasmj/Figma-MCP-Write-Bridge) (TS, 4★)【13†L282-L290】<br>[guhcostan/figmind](https://github.com/guhcostan/figmind) (TS, 0★) |
| **Desktop Bridge App**| Same as plugin-bridge, plus an Electron/Node “system tray” app. Manages MCP servers.  | Same as plugin-bridge (full read/write). Often auto-manages multiple agents and ports【15†L360-L368】.  | Additional setup/install (Electron app); still needs Figma Desktop.  | [grab/TalkToFigmaDesktop](https://github.com/grab/TalkToFigmaDesktop) (TS/Electron, 26★)【15†L360-L368】<br>[grab/cursor-talk-to-figma-mcp](https://github.com/grab/cursor-talk-to-figma-mcp) (TS, 6500★)【32†L297-L305】 |
| **Figma REST API**  | Any server/CICD, Figma PAT or OAuth. No desktop.    | *Read*: file JSON (all nodes, vectors), images exports, components, styles, comments【35†L83-L91】. Can batch-export frames/images. Great for analysis or asset extraction.   | *Write*: **none**. Cannot create or modify nodes. Rate-limited per-token (Tier1 ~10/min, Tier2 ~25–100/min depending on plan)【37†L128-L135】. Global usage counts against one PAT user. | [figma-export](https://github.com/figma-export/figma-export) (TS) – tokens/style export |

## Open-Source Project Highlights  

Below is a prioritized list of representative MCP integration projects and tools. These can serve as models or starting points.

| Repo (Link)                                   | Approach              | Language    | Stars | Maturity/Notes                                     | Key Files to Inspect                     |
|-----------------------------------------------|-----------------------|-------------|-------|----------------------------------------------------|-----------------------------------------|
| [grab/cursor-talk-to-figma-mcp](https://github.com/grab/cursor-talk-to-figma-mcp) | Desktop Bridge (Cursor) | TypeScript  | 6.5k★【43†L39-L46】 | Very mature; widely used. Supports Cursor + others.  | `src/talk_to_figma_mcp/server.ts` (MCP server implementation), `src/cursor_mcp_plugin/manifest.json` (Figma plugin). |
| [southleft/figma-console-mcp](https://github.com/southleft/figma-console-mcp)  | Plugin-Bridge (Node)  | TypeScript  | 923★【38†L1-L4】 | Full-featured design-Creation MCP. NPX setup.        | `figma-desktop-bridge/manifest.json` (plugin), `src/index.ts` (server entry), `src/api-tools.ts` (tool definitions). |
| [grab/TalkToFigmaDesktop](https://github.com/grab/TalkToFigmaDesktop)         | Desktop App (Electron)| TypeScript  | 26★【39†L1-L4】 | Electron app with GUI. Simplifies multi-client.      | `src/main.ts` (Electron main process), `src/socket.ts` (MCP stdio server), `plugin/manifest.json`. |
| [magic-spells/figma-mcp-bridge](https://github.com/magic-spells/figma-mcp-bridge) | Plugin-Bridge (Node)  | JavaScript  | 31★【40†L1-L4】 | Claude-oriented. Example for writing frames, shapes. | `src/index.js` (MCP server), `plugin/manifest.json` (Figma plugin). |
| [firasmj/Figma-MCP-Write-Bridge](https://github.com/firasmj/Figma-MCP-Write-Bridge) | Plugin-Bridge (Node)  | TypeScript  | 4★【41†L7-L10】  | Simple example of write-only MCP server.             | `figma-write-bridge.ts`, `server.ts` (bridge and MCP server). |
| [Antonytm/figma-mcp-server](https://github.com/antonytm/figma-mcp-server)      | Plugin-Bridge (Node)  | TypeScript  | 120★ | Early prototype. Uses socket.io.                     | `mcp/server.ts` (Express+WS server), `plugin/manifest.json`. |
| [guhcostan/figmind](https://github.com/guhcostan/figmind)                    | Plugin-Bridge (Node)  | TypeScript  | 0★  | Minimal Cursor integration.                         | `src/talk_to_figma_mcp/server.ts`, `packages/figma-plugin/manifest.json`. |
| Figma Official MCP (Docs)                     | Remote & Desktop      | –           | –     | The “source of truth”. Read Figma’s Dev Mode guides【17†L119-L127】【25†L78-L87】. | Figma DevDocs (e.g. [remote-server-installation](https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/)). |
| Figma REST API (Docs)                         | REST API (Cloud)      | –           | –     | Official API docs. Explains scopes & limits【35†L83-L91】【37†L128-L135】. | developers.figma.com/rest and auth guides. |

## Recommended Architecture for Aixle  

**Goal:** Run LLM agents in cloud, but produce **editable Figma designs** as output. Given the constraints above, a hybrid approach is advised:

- **Design Generation (Cloud Agent):** Aixle’s cloud agents can generate a *design specification* (AST, JSON, or code) representing the UI. They can call the Figma REST/MCP remote API to *fetch* any existing context (e.g. design tokens or components) to inform the design.  
- **Execution in Figma (User-side Bridge):** To *apply* the design, use a **local MCP bridge** on the user’s machine. This could be one of the open-source MCP servers or a lightweight plugin. For example, Aixle could output a JSON AST and then an NPX script (or plugin command) on the user’s side reads this AST and executes Figma plugin API calls to create the frames. Another pattern: Aixle could instruct a CLI (e.g. a Docker container) to run figma-console-mcp with a predefined input (perhaps via `figma_batch_import` tool) to build the design. The key is that some process with Figma desktop open will consume the agent’s plan and make the actual Figma edits.  

**Trade-offs:**  
- *Local Requirement:* This means Aixle’s generated designs are not applied automatically in a remote Figma file; the user must run a bridge or have a local agent process. However, it preserves full editability and fidelity.  
- *Tooling:* We recommend leveraging existing open-source bridges. For instance, Aixle could bundle [figma-console-mcp](https://github.com/southleft/figma-console-mcp) in “execute” mode: the agent’s plan is translated into MCP calls (like `figma_execute`) which the console server runs via the plugin. Alternatively, develop a Aixle-specific Figma plugin that reads a JSON file (perhaps from Clipboard or a server) and creates nodes.  

**Migration Steps:** Start with cloud-only prototypes that use the REST API to *simulate* design output (e.g. generate images or a static report). Then introduce a small local agent: for example, run [Cursor](https://cursor.com/) with Aixle’s MCP commands by adding Aixle as a custom MCP. Finally, refine into an integrated bridge plugin.  

**Security:** Users must trust Aixle’s process on their machine. We suggest Aixle provide *scripted tools* rather than an always-open service, so the user explicitly triggers design application. Access tokens should have minimal scopes (only needed files).  

**Concise Recommendation:** Use Figma’s official MCP (for reading only) during cloud agent planning, but rely on a **Node/WebSocket bridge on the user side for writing**. In practice, an architecture like Southleft’s Figam Console MCP or Grab’s Cursor-MCP with a Aixle plugin will give agents full design control while still letting them run “in the cloud” during reasoning. This balances scalability (cloud LLM) with the necessity of a live Figma environment for output.

