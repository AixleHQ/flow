// Frame-by-frame renderer for Claude Design animation scenes.
// Drives the Stage's data-om-seek-to-time-frame protocol, screenshots each frame.
const { chromium } = require('playwright-core');
const fs = require('fs');
const os = require('os');
const path = require('path');

const URL = process.env.SCENE_URL || 'http://127.0.0.1:8944/index.html';
const OUT = process.env.FRAMES_DIR || path.join(__dirname, 'frames');
const FPS = +(process.env.FPS || 30);
const W = +(process.env.STAGE_W || 1080);
const H = +(process.env.STAGE_H || 1920);

function findChromium() {
  const base = path.join(os.homedir(), 'Library/Caches/ms-playwright');
  const dirs = fs.readdirSync(base).filter(d => d.startsWith('chromium-')).sort();
  if (!dirs.length) throw new Error('no chromium in ms-playwright cache');
  const d = dirs[0];
  return path.join(base, d, 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ executablePath: findChromium(), headless: true });
  const page = await browser.newPage({ viewport: { width: W, height: H + 60 }, deviceScaleFactor: 1 });
  page.on('console', m => { if (m.type() === 'error') console.log('[console.error]', m.text().slice(0, 200)); });
  await page.goto(URL, { waitUntil: 'networkidle' });

  const svgSel = 'svg[data-om-exportable-video-with-duration-secs]';
  await page.waitForSelector(svgSel, { timeout: 30000 });
  await page.evaluate(() => document.fonts.ready);
  // wait for font inlining flag (best effort)
  await page.waitForFunction(
    (sel) => document.querySelector(sel)?.getAttribute('data-om-fonts-inlined') === 'true',
    svgSel, { timeout: 15000 }
  ).catch(() => console.log('fonts-inlined flag timeout — continuing'));

  const duration = await page.$eval(svgSel, el => +el.getAttribute('data-om-exportable-video-with-duration-secs'));
  const total = Math.round(duration * FPS);
  console.log(`duration=${duration}s fps=${FPS} frames=${total}`);

  const el = await page.$(svgSel);
  for (let i = 0; i < total; i++) {
    const t = i / FPS;
    await page.evaluate(({ sel, t }) => {
      const svg = document.querySelector(sel);
      svg.dispatchEvent(new CustomEvent('data-om-seek-to-time-frame', { detail: { time: t } }));
      return new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    }, { sel: svgSel, t });
    await el.screenshot({ path: path.join(OUT, `f-${String(i).padStart(4, '0')}.png`) });
    if (i % 60 === 0) console.log(`frame ${i}/${total}`);
  }
  await browser.close();
  console.log('frames done');
})().catch(e => { console.error(e); process.exit(1); });
