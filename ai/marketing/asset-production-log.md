# Asset Production Log — Aixle Flow OSS Launch

Running log of every produced marketing asset, its production details, and reusable pipeline learnings. Companion to `oss-promo-strategy-2026-07-02.md` (the plan) — this file records what actually got made.

## Production tooling status (2026-07-02)

| Tool | Status | Notes |
|---|---|---|
| Kling CLI (`kling`, @klingai/cli-global 0.1.1) | ✅ primary AI-video path | Browser-OAuth'd, free membership, ~15.1k credits left. Models up to Kling 3.0 (t2v + i2v + t2i + i2i) |
| Gemini API key | ⚠️ text-only | Image/video models return 429 on free tier (daily quota = 0); needs billing enabled on the Google project. Key NOT persisted to shell profile |
| Playwright + ffmpeg 8 + Remotion (Node 24) | ✅ ready | Screen-capture + programmatic video pipeline; no keys needed |
| fal.ai / Replicate | ⏳ not set up | Research verdict: fal.ai first if one is chosen (video-first, day-0 models, fixed per-output pricing, official MCP). Same official-model prices on both |
| ImageMagick / cwebp / jpegoptim | ❌ missing | `brew install imagemagick webp jpegoptim` — needed for README GIF/WebP size budgets |

### Kling CLI operational learnings (hard-won, do not relearn)

- **Free tier = ONE concurrent generation.** Parallel submissions fail with HTTP 400 "Non-subscribers can only run one generation task at a time". Batch sequentially.
- **`query_tasks --poll N <id>`** returns a DIFFERENT response shape: `body.generations[].result.works[].url` (wrapped), vs plain `query_tasks <id>`: `body.works[].url`. Parse both.
- **Always log `generation_id` immediately after submit** — there is no server-side list API in the CLI; a lost id means the video is only retrievable manually from the kling.ai web library.
- Result URLs **expire in 24 hours** — download immediately.
- Free membership adds a **KlingAI watermark** (bottom-right). Options: crop/delogo via ffmpeg, paid tier, or route final hero clips through fal.ai (no watermark, ~$0.35/5s clip).
- Credit costs observed: v3.0-turbo 5s = 40, 10s = 80; v3.0 full 5s = 30 (cheaper than turbo AND higher-fidelity photoreal — prefer it for premium shots); v2.5 with audio 5s = 15 (cheapest, includes generated audio).
- Kling renders fast: ~30–60 s per 5 s clip.

## Batch 1 — AI b-roll library (2026-07-02)

Location: `~/Movies/aixle-promo/batch-1/` (16 mp4 + frames + `contact-sheet.png`).
Style system: dark charcoal (#0A0908) matte surfaces, ember-orange (#E0582E) glow, green terminal accents, "restrained engineering" aesthetic, no people, no text overlays (titles get added programmatically later, per video-skill rule that AI can't render readable text).

Credits spent: ~605 total (incl. 335 lost-and-regenerated duplicates — first takes still live in the kling.ai web library as alternate seeds). Balance after batch: ~15.1k.

| # | Key | Model / spec | Verdict | Intended use |
|---|---|---|---|---|
| 1 | hero-original | v3.0-turbo 5s 16:9 | ★★★ | The original test — card→container→terminal story; README hero candidate |
| 2 | hero-topdown | v3.0-turbo 5s 16:9 | ★★★ | Top-down card + wireframe cube + circuit rays; README hero / X teaser |
| 3 | hero-vertical | v3.0-turbo 5s 9:16 | ★★★ | Vertical slot + hexagonal wireframe; Shorts/Reels/Stories |
| 4 | hero-square | v3.0-turbo 5s 1:1 | ★★★ | Symmetric square hero; LinkedIn/IG feed |
| 5 | card-snap-audio | v2.5 5s 16:9 + native audio | ★★☆ | White-wireframe variant WITH generated sound (click + hum + ambient); audio-on teasers |
| 6 | sandbox-cubes | v3.0-turbo 5s 16:9 | ★★★ | Glass cubes with independent terminals; Docker-sandbox deep-dive visuals |
| 7 | parallel-waves-v3full | v3.0 full 5s 16:9 | ★★★ | Photoreal circuit lanes; Temporal/DAG story premium shot |
| 8 | parallel-waves | v3.0-turbo 5s 16:9 | ★★☆ | Turbo take of the same concept; b-roll alternate |
| 9 | ci-gate | v3.0-turbo 5s 16:9 | ★★☆ | Orange stream through red→green gate; CI-gates b-roll |
| 10 | persona-core-swap | v3.0-turbo 5s 16:9 | ★★★ | Core swapped in socket; runtime-agnostic personas (idea #12) |
| 11 | token-meter | v3.0-turbo 5s 16:9 | ★★★ | Nixie-style digit reels + gauge; "The Bill" monthly post (idea #15) |
| 12 | terminal-macro | v3.0-turbo 5s 16:9 | ★★★ | Green glyph macro + orange LED bokeh; universal b-roll |
| 13 | container-fleet-10s | v3.0-turbo 10s 16:9 | ★★★ | TRON-like wireframe container fleet w/ cranes; signature-video epic shot |
| 14 | vault-open | v3.0-turbo 5s 16:9 | ★★☆ | Vault + spark constellation; drifted toward stone/fantasy — usable teaser, regenerate for "engineered" look if needed |
| 15 | outbox-relay-v2 | v3.0-turbo 5s 16:9 | ★★☆ | Stylized envelopes + clockwork wheels; outbox post (idea #8) |
| 16 | outbox-relay (v1) | v3.0-turbo 5s 16:9 | ❌ reject | Photoreal + human hand in frame (violated "no people") — kept for reference |

All clips carry the KlingAI watermark (free tier) — fine for social drafts, strip/replace for final hero assets.

## Batch 2 — style exploration (2026-07-02)

Location: `~/Movies/aixle-promo/batch-2-styles/` (6 mp4 + `style-comparison.png`). Trigger: batch-1's "cinematic sci-fi" look drifted from the brand's graphic restraint. Same hero concept (card → cube with terminal) re-rendered in 5 styles + one image-to-video run from a brand-exact HTML reference. ~165 credits.

| Key | Approach | Verdict | Takeaway |
|---|---|---|---|
| i2v-board-ref | **HTML → Playwright screenshot → Kling v2.6 image_to_video** (15 cr) | ★★★ VALIDATED | Layout/colors/typography preserved near-pixel-perfect; card animates down the column as prompted. Small terminal text degrades during motion; minor UI hallucination (extra button). **This is the brand-exact motion pipeline**: build the frame in HTML with real tokens, animate with minimal-motion prompts. Reference frame: `~/Movies/aixle-promo/refs/board-ref.png` (source: scratchpad board-ref.html) |
| style-isometric-matte | t2v v3.0 | ★★★ | Slate tray + frosted cube + copper plate, zero glow, craft-like. Distinctive hero style for social covers — nothing in the n8n/Dify space looks like this |
| style-blueprint | t2v v3.0 | ★★★ | CAD schematic, self-drawing lines. Perfect for architecture-post headers (outbox, sandbox deep-dives) |
| style-flat-vector | t2v v3.0 | ★★☆ | Premium 2.5D flat; closest t2v to brand graphic language |
| style-light-theme | t2v v3.0 | ★☆☆ | Went "industrial hardware" instead of light UI; gibberish pseudo-text everywhere |
| style-ascii | t2v v3.0 | ★☆☆ | Fun but noisy; glyph tables read as gibberish |

**Style canon going forward:**
1. **i2v from brand HTML frames** — the workhorse for anything showing "the product" (UI stories, feature spotlights). Text-true, brand-true.
2. **isometric-matte** — signature style for social hero clips and covers.
3. **blueprint** — engineering blog post headers.
4. Batch-1 "cinematic glow" — keep as b-roll garnish inside edited videos, not as the face of the brand.

**Prompting law learned:** any t2v style that *implies* UI text makes Kling render gibberish → never imply text in t2v; text comes only from i2v HTML references or programmatic (Remotion) overlays.

## Batch 3 — brand-exact UI animations from HTML refs (2026-07-02)

Location: `~/Movies/aixle-promo/batch-3-ui/` (4 mp4). Refs: `~/Movies/aixle-promo/refs/` (HTML sources in session scratchpad: board-drag.html with `?frame=a|b` keyframe toggle, workflow-run.html, cost-dashboard.html, persona-dropdown.html). Demo project renamed **copperline** (tickets CPL-xxx) — "palad" removed from all public-facing assets. ~60 credits.

| Key | Motion | Verdict |
|---|---|---|
| ui-workflow-run | 3 parallel progress bars fill, chips flip green | ★★★ text crisp, motion as directed; gate card greens early (harmless) |
| ui-cost-dashboard | bars grow Mon→Sun, $ counter ticks up | ★★☆ counter-tick effect is real ($48.13 mid-roll); Kling re-invented final bar heights |
| ui-persona-swap | cursor glides down, highlight moves to Codex | ★★☆ cursor path correct; check end-state highlight |
| ui-board-drag | card drags across columns into dashed slot | ★☆☆ trajectory perfect, but LARGE motion at 720p corrupts small card text into gibberish |

**Prompt discipline (validated):** direct like a shot list — what moves, from where, along what path, to where, what happens on arrival, and ALWAYS end with "everything else stays perfectly still / static camera / no zoom / crisp sharp text".

**Free-tier limits found:** `--tailImage` (first+last keyframe interpolation) requires resolution=1080p, and 1080p is not available on free membership → tail-frame workflow needs a paid Kling tier.

**UI-motion tiering (the rule going forward):**
1. **Subtle in-place motion** (progress bars, counters, hovers, pulses) → Kling i2v from HTML ref, 15 credits, text survives.
2. **Large displacement motion** (card drags, page transitions) → NO AI: animate in CSS/JS in the HTML ref itself and screen-record with Playwright — pixel-perfect, free, reproducible. (Also exactly the pipeline the README hero GIF needs.)
3. **Non-UI cinematic/b-roll** → Kling t2v in the approved styles (isometric-matte, blueprint).

## Batch 4 — Claude Design motion pipeline (2026-07-02) — NEW PRIMARY VIDEO PATH

`~/Movies/aixle-promo/batch-4-design/browser-triggers-1080x1920.mp4` — 20 s vertical (1080×1920) social ad rendered from the user's claude.ai/design project "Браузер с AI триггерами" (project 48745c1f-361d-4f1b-a213-9ee00eaa0dcd). Camera moves, cursor with click rings, trigger picker → workflow build → live run with status chips → Aixle endcard. Crisp text, exact brand tokens, no watermark, $0.

**Pipeline (tools in `ai/marketing/dc-render/`):**
1. Author/iterate scene in Claude Design (JSX Stage/Sprite engine: interpolate/easing/camera World).
2. Pull files via DesignSync tool (animations.jsx, scene.jsx, assets).
3. Local harness (index.html: React+Babel UMD + Google Fonts) served over localhost.
4. `render.js` (playwright-core + ms-playwright Chromium at `chromium-*/chrome-mac-arm64/Google Chrome for Testing.app/...`) drives the engine's `data-om-seek-to-time-frame` event per frame → PNG per frame.
5. ffmpeg assemble; ALWAYS pass `-vf scale=W:H` (element screenshots can be 1px off; yuv420p needs even dims).

Gotchas: DesignSync get_file caps at 256 KiB → large binary assets (Ring_Orange.png) come back truncated; regenerate locally (gen-ring.js draws the torus via canvas) or keep masters outside the project.

Batch 4 assets:
- `browser-triggers-1080x1920.mp4` — 20 s, trigger picker → Slack-triage run → endcard (scene from the user's Design project).
- `sandbox-isolation-1080x1920.mp4` — 20 s, message pillar #1: card → live docker terminal → 3 parallel isolated sandboxes → "Full isolation by default" → endcard. Authored fully locally (scene-sandbox.jsx) — Claude Design NOT required for authoring, only for the user's visual iteration; DesignSync write path available when the user wants scenes in the project.
- Scene prompt backlog: `ai/marketing/design-scene-prompts.md` (8 scenes mapped to the message hierarchy; sandbox #1 done, next: triggers anthology, durable runs).

**Video tiering (final):** 1) Claude Design scenes → this pipeline = PRIMARY for all product/UI motion and social ads. 2) Kling i2v from HTML refs = quick subtle-motion drafts. 3) Kling t2v (isometric-matte/blueprint) = cinematic b-roll garnish. 4) Playwright screencasts of the real app = README hero / honest demos.

## Next production steps

1. Post-production layer (video skill pipeline): Remotion/Hyperframes brand titles + captions over selected clips; ffmpeg crops/exports per platform; watermark handling for hero assets.
2. Screen-capture assets (the actual product): Playwright-scripted README hero GIF + capability loops — these are the strategy's non-negotiable Phase 0 items; AI b-roll is garnish, real UI is the meat.
3. Image side: enable Google billing for Nano Banana, or set up fal.ai — needed for og:images/social stills beyond screenshots.
4. `brew install imagemagick webp jpegoptim` before README GIF work.
