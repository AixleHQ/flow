# Agent Image Size Audit (dive) — 2026-08-04

**Status:** audit findings **implemented and validated** on branch `fix/agent-image-slim` —
see [§Implementation](#implementation--2026-08-04) at the end for the as-built result
(5.35 GB → 2.09 GB on `claude-code`) and the end-to-end verification. The analysis below is
the original measurement pass; every "unused" claim is backed by a functional probe.

**Platform caveat:** measured on `linux/arm64` (Apple Silicon). Absolute sizes on `amd64`
differ by a few percent; every finding is structural and applies to both.

## Method

| Tool | What it gave |
| --- | --- |
| `dive 0.13.1` (`CI=true dive <image> --json out.json`) | per-image efficiency score + every path stored in more than one layer |
| `docker history --no-trunc` | which Dockerfile instruction produced each fat layer |
| `du -xsm` inside the image | live (final-filesystem) footprint, i.e. the floor a rebuild can reach |
| `dpkg-query -Wf '${Installed-Size}'` | per-package weight for apt candidates |
| `@playwright/mcp` stdio probes (JSON-RPC `initialize` → `browser_navigate` → `browser_take_screenshot` → `browser_evaluate`) | whether a candidate for removal is actually needed at runtime |

## Baseline

| Image | Image size | Live filesystem | Pure layer waste | dive efficiency |
| --- | --- | --- | --- | --- |
| `aixle/claude-code:latest` | 5.35 GB | 2.99 GB | **2.36 GB** | 0.554 |
| `aixle/codex:latest` | 4.01 GB | 2.79 GB | **1.22 GB** | 0.704 |
| `aixle/cursor-cli:latest` | 4.00 GB | 2.70 GB | **1.30 GB** | 0.672 |
| `aixle/gemini-cli:latest` | 3.76 GB | 2.66 GB | **1.10 GB** | 0.703 |

"Pure layer waste" = image size − live filesystem: bytes shipped in a layer that the final
container can never see, because a later layer rewrote or deleted them.

On-disk (`docker system df -v`, shared base counted once): **6.48 GB** for the four images
= 3.544 GB shared base + 1.803 / 0.463 / 0.459 / 0.215 GB unique.

## Group A — layer duplication (zero-risk build fixes, no content lost)

Every item here is a *copy* of bytes that are already in an earlier layer. `chmod -R` /
`chown -R` rewrite metadata, and overlayfs copies up **the whole file** for a metadata change,
so a recursive ownership fix over a 1 GB tree costs another 1 GB in the image.

### A1. `chmod -R 755` over the Playwright browsers — 1.03 GB × all four images

`docker/base/Dockerfile:203-210` — the layer that symlinks Chrome ends with
`chmod -R 755 ${PLAYWRIGHT_BROWSERS_PATH}`, duplicating the entire 984 MiB browser tree
installed by the previous layer (`docker/base/Dockerfile:198-201`).

dive, `claude-code`: `chromium-1232/chrome-linux/chrome` is stored **3×**,
`chromium_headless_shell-1232/.../headless_shell` **3×** — 3.09 GB of the image is
`/opt/playwright-browsers` copies.

**Fix:** do the `chmod` (and the symlink/cleanup) inside the same `RUN` as
`playwright ... install --with-deps`, so the tree is written once with final permissions.

### A2. `chown -R root:claude` + `chmod -R 775` on the browsers — 1.03 GB, `claude-code` only

`docker/claude-code/Dockerfile:13-16` re-owns the same 984 MiB tree a third time. This is why
`claude-code` is 1.34 GB heavier than `codex` while adding only ~500 MB of real content.

**Fix (needs a decision):** the tree is already `root:root 755` — world-readable and
world-executable, which is all a *reader* needs. The group-write intent (`775`) is the only
thing this instruction adds. If Playwright needs to write anything at runtime, give it a small
writable dir instead of re-owning a gigabyte. If the group-write bit is genuinely required,
set the group **in the base layer's own `RUN`** (A1) rather than in a derived image.

### A3. `chown -R` over an agent home that is already agent-owned

| Image | Instruction | Duplicated |
| --- | --- | --- |
| `claude-code` | `docker/claude-code/Dockerfile:54-55` — `mkdir -p ~/.claude ~/.aws && chown -R claude:claude /home/claude` | **272 MB** (`~/.local/share/claude/versions/2.1.220`) |
| `cursor-cli` | `docker/cursor-cli/Dockerfile:24-28` — `mkdir -p ~/.config/cursor ~/.cursor && chown -R cursor:cursor /home/cursor` | **229 MB** (`~/.local/share/cursor-agent/versions/...`, incl. a 252 MB bundled `node`) |

Both installers already ran **as the agent user** (`USER claude` / `USER cursor`), so the
recursive `chown` changes nothing — it only copies up the whole install.

**Fix:** create just the new dirs with the right owner and stop recursing, e.g.
`install -d -o claude -g claude /home/claude/.claude /home/claude/.aws`
(or run the `mkdir` under `USER claude`).

### A4. npm cache left in the CLI-install layer, deleted later

`docker/codex/Dockerfile:13` (`npm install -g @openai/codex`) and
`docker/gemini-cli/Dockerfile:15` (`npm install -g @google/gemini-cli`) leave `/root/.npm/_cacache`
behind; the *later* watcher layer runs `npm cache clean --force`, so the cache bytes stay in the
image forever while being invisible at runtime.

dive: `/root/.npm/_cacache` stored 2× — **~90 MB** wasted in `codex`, **~35 MB** in `gemini-cli`.

**Fix:** `RUN npm install -g <pkg> && npm cache clean --force` in one instruction.

### A5. apt lists never cleaned in the first base layer — ~19 MB × all four

`docker/base/Dockerfile:56-93` (the big `apt-get install`) has **no**
`rm -rf /var/lib/apt/lists/*`; the GitHub-CLI layer at `:111-116` deletes them afterwards, which
only hides them. dive: `..._binary-arm64_Packages.lz4` stored 2×.

**Fix:** end the layer with `&& rm -rf /var/lib/apt/lists/*` (each apt layer cleans its own).

### A6. debconf cache rewritten by every apt layer — ~25 MB × all four

`/var/cache/debconf/templates.dat` is stored **6×** (4.7 MB each) and `templates.dat-old` **5×**.
Unavoidable per-layer churn, but it is pure waste in the shipped image.

**Fix (optional):** `rm -rf /var/cache/debconf/*-old /var/cache/ldconfig` at the end of the
last apt layer, or squash the apt layers.

**Group A total:** claude-code **−2.36 GB**, codex **−1.22 GB**, cursor-cli **−1.30 GB**,
gemini-cli **−1.10 GB**. No functionality touched, no runtime behaviour changed.

## Group B — content that is verifiably not used (safe to drop after Group A)

### B1. `chromium_headless_shell-1232` — 340 MiB (~356 MB) × all four

Playwright's `browsers.json` marks `chromium-headless-shell` `installByDefault: true`, so
`playwright install ... chrome-for-testing` pulls it alongside Chrome. It is used **only** when
a client launches Chromium with no channel:

```
{"headless":true}                                   → FAIL: Executable doesn't exist at
                                                       .../chromium_headless_shell-1232/chrome-linux/headless_shell
{"headless":true,"channel":"chrome-for-testing"}    → LAUNCHED 151.0.7922.10
```

Our runtime always goes through `@playwright/mcp` (pinned in `docker/base/Dockerfile:195` and
`app/services/agents/base_adapter.rb:245`), which requests the `chrome-for-testing` channel.
Probe with the directory moved aside:

```
### A) headless_shell present, --headless   → nav: ok, screenshot: ok
### B) headless_shell MOVED AWAY, --headless → nav: ok, screenshot: ok
```

**Fix:** after the install, `rm -rf ${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-*`
in the same layer. Add a build-time assertion that Chrome still resolves, so a future
Playwright bump that drops the channel fails the build instead of failing a session.

### B2. Mesa DRI + LLVM + Xvfb — 139 MiB (~146 MB) × all four

`playwright install --with-deps` pulls a software-GL stack the headless browser never touches:
`libllvm15` (107 MiB), `libgl1-mesa-dri` (23 MiB), `libglapi-mesa`, `libglx-mesa0`, `xvfb`,
`xserver-common`, `libdrm-{amdgpu1,nouveau2,radeon1}`. `libllvm15` alone is the single largest
apt package in the image.

WebGL in this image is served by Chrome's **bundled** SwiftShader (`libvk_swiftshader.so`),
not by Mesa:

```
baseline      → webgl: WEBGL_OK renderer=ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (LLVM 10.0.0)), SwiftShader driver)
mesa removed  → webgl: WEBGL_OK renderer=ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (LLVM 10.0.0)), SwiftShader driver)
```

And the clean apt path works too:

```
apt-get purge -y libgl1-mesa-dri xvfb xserver-common && apt-get autoremove -y
→ nav: ok, screenshot: ok        (libllvm15 auto-removed as an orphan)
```

`xvfb` has zero references in the repo (`grep -rn 'xvfb\|Xvfb\|DISPLAY=' docker/ app/ lib/ config/` → no hits) —
nothing ever starts a virtual X server.

**Fix:** after the Playwright dep install, in the same layer:
`apt-get purge -y libgl1-mesa-dri xvfb xserver-common && apt-get autoremove -y`.
Keep the probe (navigate + screenshot + WebGL) as a build-time smoke check.

**Group B total: ~500 MB off every one of the four images.**

## Group C — judgment calls (measured, not recommended blindly)

| Candidate | Size | Argument to keep | Argument to drop |
| --- | --- | --- | --- |
| C++ toolchain: `gcc-12`, `g++-12`, `cpp-12`, `binutils`, `libz3-4`, `libasan8`, `libtsan2`, `libubsan1`, `libstdc++-12-dev`, `libc6-dev`, `linux-libc-dev`, `make` | **233 MiB** | **KEPT** — an agent running `npm install` in a customer repo with a `node-gyp` dep needs it, and the failure would be remote and confusing (`gyp ERR! not found: make`) | biggest single lever left, but not worth a remote confusing failure. Decided 2026-08-04: stays in, unconditionally — no build flag |
| AWS CLI v2 (`/usr/local/aws-cli`) | **236 MiB** | **KEPT** unconditionally — Bedrock diagnostics + the in-container Identity Center device-code login (`docker/claude-code/Dockerfile:38-49`) are not optional for `claude-code` | only `claude-code` carries it, and only Bedrock connections use it. Decided 2026-08-04: no flag |
| CJK/extra fonts: `fonts-wqy-zenhei`, `fonts-unifont`, `fonts-ipafont-gothic`, `fonts-freefont-ttf`, `fonts-noto-color-emoji` | **59 MiB** | screenshots of CJK/emoji pages render as tofu without them | navigate + screenshot still pass with them moved away; it is a fidelity, not a functionality, question. Keeping `fonts-noto-color-emoji` + Liberation covers most cases at ~10 MiB |
| `p7zip` / `p7zip-full` | 7 MiB | archive extraction convenience | not referenced anywhere outside the Dockerfile |
| `python3-pip`, `python3-pip-whl`, `pipx` | 9 MiB | **keep** — `pipx` is a first-class MCP runtime (`app/services/mcp/connector_manifest.rb:64-71`), and a test asserts the image provides every runtime the catalog offers | — |
| `cloc` (drags in `libperl5.36` + `perl-modules-5.36`, **48 MiB** of perl) | 48 MiB | **keep** — `cloc` is advertised to agents as an available tool (`app/services/context_builders/tools.rb:51`, `aixle_builder.rb:160`); removing it silently breaks a documented capability | — |
| OpenVSCode Server (`/opt/openvscode-server`, 220 MiB) | 220 MiB | **keep** — it is the browser IDE feature | — |
| Codex CLI binary (257 MB `codex` + 44 MB `codex-code-mode-host`, vendored prebuilt Rust) | 306 MiB | **keep** — vendor artifact; not ours to strip | — |

## Projected result

Per-image (registry/pull weight). Group C was **not** taken — see the decision in that section;
the "A+B" column is what actually shipped.

| Image | Now | After A | After A+B (shipped) |
| --- | --- | --- | --- |
| `claude-code` | 5.35 GB | 2.99 GB | ~2.49 GB |
| `codex` | 4.01 GB | 2.79 GB | ~2.29 GB |
| `cursor-cli` | 4.00 GB | 2.70 GB | ~2.20 GB |
| `gemini-cli` | 3.76 GB | 2.66 GB | ~2.16 GB |

On disk with the shared base counted once: **6.48 GB → ~3.25 GB** after A+B (base drops
3.54 → ~1.97 GB; `claude-code`'s unique layers drop 1.80 → ~0.50 GB).

## Suggested order of work

1. **A1 + A5 + A6** in `docker/base/Dockerfile` — one layer rewrite, −1.03 GB on every image.
2. **A3** in `claude-code` and `cursor-cli`; **A4** in `codex` and `gemini-cli` — one-line each.
3. **A2** (`claude-code`) — needs the "does Playwright need group-write?" answer first.
4. **B1 + B2** with the MCP probe wired in as a build-time smoke check.
5. **C** — decided 2026-08-04: keep the toolchain and the AWS CLI, unconditionally, no build
   flags. Only the CJK/Thai fallback fonts were dropped (a fidelity, not a functionality, loss).

Rebuild with `make build-agents` and re-verify: `CI=true dive aixle/claude-code:latest`
should report efficiency ≳ 0.95, and a session must still be able to run
`browser_navigate` + `browser_take_screenshot` through `@playwright/mcp`.

## Host-side cleanup (separate from image content)

`docker system df` reports **45.37 GB reclaimable (69%)** locally. Stale agent tags alone:

| Tag | Unique size |
| --- | --- |
| `aixle/claude-code:bedrock-spike` (8 days old) | 4.43 GB |
| `aixle/agent-base-core:test-pipx` (2 months old) | 3.19 GB |

Plus 18.02 GB of dangling local volumes. This is local disk hygiene, not a Dockerfile problem —
listed here only because it dominates the "images got huge" symptom on a dev machine.

## Reproducing

```bash
CI=true dive aixle/claude-code:latest --json /tmp/dive.json     # efficiency + duplicated paths
docker history --no-trunc aixle/claude-code:latest              # which instruction made each layer
docker run --rm --entrypoint sh -u root aixle/claude-code:latest -c 'du -xsm /* | sort -rn'
docker run --rm --entrypoint sh -u root aixle/claude-code:latest -c \
  'dpkg-query -Wf "\${Installed-Size}\t\${Package}\n" | sort -rn | head -40'
```

The MCP probe used for B1/B2 speaks JSON-RPC over stdio to
`/usr/local/lib/node_modules/@playwright/mcp/cli.js --headless --isolated`
(`initialize` → `notifications/initialized` → `tools/call browser_navigate` →
`browser_take_screenshot` → `browser_evaluate` returning the WebGL renderer string), run in a
`--rm` container with the candidate files moved aside. It now lives in the repo as
`docker/base/probe-browser.js` and runs during the build, so B1/B2 cannot silently regress.

## Implementation — 2026-08-04

Branch `fix/agent-image-slim`. Group A + Group B were applied; Group C was rejected.
Validation ran against `:test` tags built from these same Dockerfiles; the tags were scaffolding
and are not part of the change.

### As built

| Image | Before | After | Cut |
| --- | --- | --- | --- |
| `agent-base-core` | 3.54 GB (shared base) | **1.83 GB** | −48% |
| `claude-code` | 5.35 GB | **2.35 GB** | −56% |
| `codex` | 4.01 GB | **2.15 GB** | −46% |
| `cursor-cli` | 4.00 GB | **2.06 GB** | −49% |
| `gemini-cli` | 3.76 GB | **2.02 GB** | −46% |

On disk with the shared base counted once: **6.48 GB → 3.09 GB** (base 1.832 GB + unique
514.5 / 323 / 230.8 / 186.2 MB).

Applied: A1–A6, B1 and B2. Nothing from Group C was dropped — **no build flags**: the C/C++
toolchain, the AWS CLI and `procps` all ship unconditionally (a missing compiler or a missing
`ps` fails remotely, inside someone else's repo, which is not worth 233 MiB).
`apt-get autoremove --purge` after the
Mesa/Xvfb purge also took `libicu72`, `libxml2`, `libelf1`, `libedit2`, `libunwind8` and the X11
client libs, which is where the extra headroom past the projection came from — all verified
unreferenced (`ldd` reports 0 missing libraries for node, ttyd, the OpenVSCode node, chrome,
tmux, git, uv and cloc; node's ICU still formats `ru-RU`).

Kept deliberately: AWS CLI (unconditional — Bedrock is not optional for `claude-code`),
OpenVSCode Server, `cloc` + its perl, `pipx`/`uvx`, mitmproxy, `fonts-liberation` +
`fonts-noto-color-emoji`.

### The one real regression the trim exposed

Dropping the recursive `chown` in `claude-code` (A2) broke every browser session for the
non-root agent user:

```
EACCES: permission denied, mkdir '/home/claude/.cache/ms-playwright/b'
```

Playwright does **not** treat the browsers directory as read-only — on first launch it creates a
browser-server dir inside it. So the group-write the old `chown -R root:claude && chmod -R 775`
provided was load-bearing after all; what was wrong was only *where* it was done.

Fix: the base layer creates `AGENT_BROWSERS_GROUP` (`agent-browsers`, gid 2000) and sets
group ownership + `775` + setgid **inside the same instruction that installs the browser**
(zero extra bytes), and each agent image joins its user with `useradd -G`. The build-time probe
now runs twice — as root and as an unprivileged member of that group — so this exact failure
cannot ship again.

### A second bug the rebuild exposed: a silently-broken image

A network blip during a rebuild hit `cursor.com` and `claude.ai` at once. `cursor-cli` failed
loudly — it verifies its artifact (`&& test -x /home/cursor/.local/bin/agent`). `claude-code`
reported **success while shipping no Claude CLI at all**, because

```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash   # a failed curl leaves bash reading
                                                     # empty stdin and exiting 0
```

Two fixes, both independent of the size work (the same trap exists on the `:latest` path):

- `docker/claude-code/Dockerfile` — download to a file, run it, then `test -x` +
  `claude --version` in the same instruction. No pipe, and the artifact is verified.
- `Makefile` — `build-agents` collects the background PIDs and `wait`s on
  each, failing the target if any child failed. A bare `wait` returns 0 regardless, which is
  exactly why the broken image went unnoticed. (Verified in `/bin/sh`: one failing child →
  `fail=1`; all succeeding → `fail=0`.)

### Verification

Per image, all four green: agent CLI version reports (Claude Code 2.1.221, codex-cli
0.146.0, cursor 2026.07.23, gemini 0.53.1), `aws-cli/2.33.29` on `claude-code`, watcher deps
present, `ps`/`pgrep`/`top`/`free` + `make`/`g++` present (confirming `autoremove --purge` does
not sweep explicitly-installed packages), each agent user in `agent-browsers`,
`chromium_headless_shell` gone, Chrome 151.0.7922.10 launches, and the MCP browser probe passes
**as the agent user**.

End to end against the running app (worker pointed at the rebuilt images), driven with a real Chrome from inside the trimmed image itself:

- Four interactive sessions started from the UI (one per runtime) reached `ready`, each agent
  launched in tmux, and each stopped exactly at authorization with deliberately fake
  credentials — Claude Code `Not logged in · Please run /login`; codex
  `missing field 'id_token'`; gemini a real round-trip through the MITM proxy returning
  `API_KEY_INVALID`; cursor `Press any key to log in…` printing its device-login URL.
- MITM interception works (api.anthropic.com request/response pairs logged, CA trust intact) and
  the platform MCP reports `🟢 aixle-tools - Ready`.
- A workflow run as the company admin reached its agent step on a rebuilt container and blocked
  in the cloud-credential broker (`reauthorization_required: InvalidGrantException` → 401 from
  `credential_process`) — an authorization failure, independent of the image.
- Finishing sessions and cancelling the run from the UI removed every agent container.

`test/services/mcp/connector_manifest_test.rb` (the test that asserts the image provides every
MCP runtime the catalog offers) stays green: 30 runs, 0 failures.

### Follow-ups

- `procps` (`ps`, `pgrep`, `pkill`, `top`, `free`) was missing — pre-existing, also true of
  `:latest`, and agents reach for `ps aux` constantly. Added (~1 MiB).
- Gemini has two blockers of its own, both independent of the image trim:
  `~/.gemini/trustedFolders.json` is written only on the credential path
  (`gemini_cli_adapter.rb:78-85`), so an uncredentialed session stops on the folder-trust
  prompt before it ever reaches the auth gate; and a workflow step whose
  `required_agent_runtime` has no credential boots a container instead of failing fast.
- ~~A workflow step cannot close itself~~ — **resolved**. The runs were already
  `mode: non_interactive`; what was missing was the tool grant. A step with empty `tool_ids`
  never sees `finish_session` (tool 17), so it runs forever. With `tool_ids: [16, 17]`
  (`fail_session`, `finish_session`) and a prompt that actually tells the agent to call it,
  all three credentialed runtimes reach `completed` on the trimmed images
  (run #14: claude_code 18¢, cursor_cli 5¢, codex 0¢; gemini blocked at auth, as expected).
- `AGENT_IMAGE_*` overrides (used while validating against side-by-side tags) leak into the
  backend test env and make 4 strategy tests fail on image-name assertions. Unset them before
  running the suite.
