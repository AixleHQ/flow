// Generates assets/Ring_Orange.png (1180x1180 glowing torus) via canvas.
const { chromium } = require('playwright-core');
const fs = require('fs');
const os = require('os');
const path = require('path');

function findChromium() {
  const base = path.join(os.homedir(), 'Library/Caches/ms-playwright');
  const dirs = fs.readdirSync(base).filter(d => d.startsWith('chromium-')).sort();
  return path.join(base, dirs[0], 'chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing');
}

(async () => {
  const browser = await chromium.launch({ executablePath: findChromium(), headless: true });
  const page = await browser.newPage();
  const dataUrl = await page.evaluate(() => {
    const S = 1180, cx = S / 2, cy = S / 2, R = 430, TH = 120;
    const c = document.createElement('canvas');
    c.width = S; c.height = S;
    const g = c.getContext('2d');
    // outer soft glow
    let gl = g.createRadialGradient(cx, cy, R - TH * 1.6, cx, cy, R + TH * 1.9);
    gl.addColorStop(0, 'rgba(224,88,46,0)');
    gl.addColorStop(0.45, 'rgba(224,88,46,0.10)');
    gl.addColorStop(0.62, 'rgba(224,88,46,0.16)');
    gl.addColorStop(1, 'rgba(224,88,46,0)');
    g.fillStyle = gl;
    g.fillRect(0, 0, S, S);
    // torus body: ring band with radial shading (dark inner edge -> bright core -> dark outer edge)
    const band = g.createRadialGradient(cx, cy, R - TH / 2, cx, cy, R + TH / 2);
    band.addColorStop(0.0, 'rgba(140,46,18,0.0)');
    band.addColorStop(0.12, 'rgba(160,52,20,0.85)');
    band.addColorStop(0.42, 'rgba(224,88,46,1)');
    band.addColorStop(0.58, 'rgba(236,106,65,1)');
    band.addColorStop(0.85, 'rgba(150,48,19,0.85)');
    band.addColorStop(1.0, 'rgba(120,38,14,0)');
    g.fillStyle = band;
    g.beginPath();
    g.arc(cx, cy, R + TH / 2, 0, Math.PI * 2);
    g.arc(cx, cy, R - TH / 2, 0, Math.PI * 2, true);
    g.fill();
    // specular highlight arc (top-left), simulates studio light on torus
    g.save();
    g.lineWidth = TH * 0.34;
    g.lineCap = 'round';
    const hl = g.createLinearGradient(cx - R, cy - R, cx + R * 0.4, cy + R * 0.2);
    hl.addColorStop(0, 'rgba(255,180,140,0.0)');
    hl.addColorStop(0.5, 'rgba(255,196,158,0.55)');
    hl.addColorStop(1, 'rgba(255,180,140,0.0)');
    g.strokeStyle = hl;
    g.beginPath();
    g.arc(cx, cy, R, Math.PI * 0.85, Math.PI * 1.55);
    g.stroke();
    // subtle lower-right darker arc for depth
    g.lineWidth = TH * 0.3;
    g.strokeStyle = 'rgba(60,20,8,0.35)';
    g.beginPath();
    g.arc(cx, cy, R, Math.PI * 0.05, Math.PI * 0.45);
    g.stroke();
    g.restore();
    return c.toDataURL('image/png');
  });
  const b64 = dataUrl.split(',')[1];
  fs.writeFileSync(path.join(__dirname, 'assets/Ring_Orange.png'), Buffer.from(b64, 'base64'));
  await browser.close();
  console.log('ring saved,', Buffer.from(b64, 'base64').length, 'bytes');
})().catch(e => { console.error(e); process.exit(1); });
