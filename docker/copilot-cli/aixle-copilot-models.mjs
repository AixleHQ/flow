#!/usr/bin/env node
// Prints the model catalogue the signed-in account can use, as JSON on stdout, for
// Agents::CopilotCliAdapter#collect_credential_metadata.
//
// The CLI has no command that lists models outside its TUI, and there is no documented
// REST endpoint for a plan's catalogue. Its Agent Client Protocol server answers
// session/new with the catalogue and the selected model's reasoning-effort levels, and
// session/set_config_option with the levels of any other model. No prompt is sent, so
// reading it costs no AI credits.
//
// A session container keeps the token in $COPILOT_HOME/aixle-token, not in the
// environment of an exec, so it is read from there when the variable is unset.
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import readline from "node:readline";

const home = process.env.COPILOT_HOME || `${process.env.HOME}/.copilot`;
const env = { ...process.env, COPILOT_AUTO_UPDATE: "false" };
const tokenFile = `${home}/aixle-token`;
if (!env.COPILOT_GITHUB_TOKEN && existsSync(tokenFile)) {
  env.COPILOT_GITHUB_TOKEN = readFileSync(tokenFile, "utf8").trim();
}

const child = spawn("copilot", ["--acp", "--stdio", "--no-auto-update", "--disable-builtin-mcps"], {
  env,
  stdio: ["pipe", "pipe", "ignore"]
});
const fail = (message) => {
  process.stderr.write(`${message}\n`);
  child.kill();
  process.exit(1);
};
const timer = setTimeout(() => fail("timed out waiting for the Copilot CLI"), 60_000);

const pending = new Map();
let nextId = 1;
readline.createInterface({ input: child.stdout }).on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }
  const resolve = pending.get(message.id);
  if (resolve) {
    pending.delete(message.id);
    resolve(message);
  }
});
child.on("exit", (code) => fail(`the Copilot CLI exited (${code})`));

const call = (method, params) =>
  new Promise((resolve) => {
    const id = nextId++;
    pending.set(id, resolve);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
const option = (options, id) => (options || []).find((o) => o.id === id);
const efforts = (options) => (option(options, "reasoning_effort")?.options || []).map((o) => o.value);

const init = await call("initialize", { protocolVersion: 1, clientCapabilities: {} });
if (init.error) fail(init.error.message);
const session = await call("session/new", { cwd: process.cwd(), mcpServers: [] });
if (session.error) fail(session.error.message);

const { sessionId, configOptions } = session.result;
const modelOption = option(configOptions, "model");
const models = [];
for (const entry of modelOption?.options || []) {
  const switched = await call("session/set_config_option", { sessionId, configId: "model", value: entry.value });
  const meta = entry._meta || {};
  models.push({
    id: entry.value,
    name: entry.name,
    description: entry.description,
    usage: meta.copilotUsage,
    price_category: meta.copilotPriceCategory,
    enablement: meta.copilotEnablement,
    reasoning_efforts: switched.error ? [] : efforts(switched.result?.configOptions)
  });
}

clearTimeout(timer);
process.stdout.write(`${JSON.stringify({ default_model: modelOption?.currentValue, models })}\n`);
child.removeAllListeners("exit");
child.kill();
process.exit(0);
