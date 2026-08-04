#!/usr/bin/env node
// Build-time (and debug-time) guard for the trimmed browser install.
//
// The base image ships ONLY the browser @playwright/mcp actually launches: the
// chrome-for-testing channel binary. Chrome's headless shell, Mesa's software GL
// stack and Xvfb are deliberately deleted (see docker/base/Dockerfile and
// docs/research/technical-agent-image-size-audit-2026-08-04.md).
//
// Those removals are only safe as long as the MCP keeps requesting the
// chrome-for-testing channel. This probe drives the MCP over stdio exactly the
// way an agent session does — navigate, screenshot, WebGL — so a Playwright bump
// that changes the default browser resolution breaks the build instead of
// breaking a live session.
//
// Usage: node /opt/probe-browser.js            (exits non-zero on any failure)

const { spawn } = require('child_process');

const MCP_CLI =
  process.env.MCP_CLI || '/usr/local/lib/node_modules/@playwright/mcp/cli.js';
const OVERALL_TIMEOUT_MS = Number(process.env.PROBE_TIMEOUT_MS || 120000);

// The MCP writes snapshots/screenshots under <cwd>/.playwright-mcp, so each run
// needs a cwd it can write — give root and the non-root build check separate ones.
const child = spawn('node', [MCP_CLI, '--headless', '--isolated'], {
  cwd: process.env.PROBE_CWD || '/tmp',
  stdio: ['pipe', 'pipe', 'pipe'],
});

let stderr = '';
let buffer = '';
let nextId = 1;
const pending = new Map();

child.stderr.on('data', (d) => {
  stderr += d;
});

child.stdout.on('data', (d) => {
  buffer += d;
  let idx;
  while ((idx = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      continue; // non-JSON chatter on stdout is not fatal
    }
    const waiter = pending.get(msg.id);
    if (waiter) {
      pending.delete(msg.id);
      waiter(msg);
    }
  }
});

const request = (method, params) =>
  new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    setTimeout(() => {
      if (pending.delete(id)) reject(new Error(`${method} timed out`));
    }, 45000);
  });

const notify = (method, params) =>
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');

const callTool = async (name, args) => {
  const res = await request('tools/call', { name, arguments: args });
  if (res.error) throw new Error(`${name}: ${JSON.stringify(res.error).slice(0, 300)}`);
  const text = (res.result?.content || [])
    .map((c) => c.text || '')
    .join('\n');
  if (res.result?.isError) throw new Error(`${name}: ${text.slice(0, 300)}`);
  return text;
};

const fail = (message) => {
  console.error(`probe-browser: FAIL — ${message}`);
  if (stderr.trim()) console.error(`probe-browser: mcp stderr tail:\n${stderr.slice(-1500)}`);
  child.kill();
  process.exit(1);
};

const watchdog = setTimeout(() => fail('overall timeout'), OVERALL_TIMEOUT_MS);

(async () => {
  await request('initialize', {
    protocolVersion: '2024-11-05',
    capabilities: {},
    clientInfo: { name: 'probe-browser', version: '1' },
  });
  notify('notifications/initialized', {});

  // 1. The browser launches at all — this is what breaks if the only remaining
  //    binary stops being the one the MCP resolves.
  await callTool('browser_navigate', {
    url: 'data:text/html,<h1 style="font-family:sans-serif">probe</h1>',
  });

  // 2. Rendering + font path work (a screenshot forces a real paint).
  const shot = await callTool('browser_take_screenshot', {});
  if (!/png|jpe?g|image/i.test(shot) && shot.length < 32) {
    throw new Error(`screenshot returned nothing useful: ${shot.slice(0, 200)}`);
  }

  // 3. WebGL comes from Chrome's bundled SwiftShader, not from Mesa.
  const webgl = await callTool('browser_evaluate', {
    function:
      "() => { const gl = document.createElement('canvas').getContext('webgl'); " +
      "if (!gl) return 'WEBGL_NONE'; " +
      "const d = gl.getExtension('WEBGL_debug_renderer_info'); " +
      "return 'WEBGL_OK ' + (d ? gl.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'renderer-unknown'); }",
  });
  if (!webgl.includes('WEBGL_OK')) throw new Error(`no WebGL context: ${webgl.slice(0, 200)}`);

  clearTimeout(watchdog);
  child.kill();
  console.log('probe-browser: OK — navigate, screenshot and WebGL all work on the trimmed browser');
  process.exit(0);
})().catch((e) => fail(e.message));
