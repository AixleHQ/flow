// The browser's side of the end-to-end run, with Playwright (Chromium), through Traefik.
//   node check.js main        the surfaces, as the owner and as a second viewer
//   node check.js again       the same terminal after the relay was killed and restarted
//   node check.js watch <ms>  holds a terminal open and reports how long until it closes
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = 'http://127.0.0.1:8088';
const TOKEN = 'e2eroutetoken0123456789abcdef00';
const T = `${BASE}/t/${TOKEN}`;
const SHOTS = '/shots';
let failed = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  (' + detail + ')' : ''}`);
  if (!ok) failed++;
};

// A ttyd client in the page: its handshake, input as the keyboard sends it, output as it comes.
const ttyd = (page, path, input, wait) =>
  page.evaluate(async ({ url, input, wait }) => {
    return await new Promise((resolve) => {
      const ws = new WebSocket(url, ['tty']);
      ws.binaryType = 'arraybuffer';
      let out = '';
      const done = (state) => resolve({ state, out });
      ws.onopen = () => {
        ws.send(JSON.stringify({ AuthToken: '', columns: 120, rows: 30 }));
        if (input) setTimeout(() => ws.send('0' + input), 700);
        setTimeout(() => { ws.close(); done('timeout'); }, wait);
      };
      ws.onmessage = (e) => {
        const d = new Uint8Array(e.data);
        if (String.fromCharCode(d[0]) === '0') out += new TextDecoder().decode(d.slice(1));
      };
      ws.onerror = () => done('error');
      ws.onclose = (e) => done('closed ' + e.code);
    });
  }, { url: `ws://127.0.0.1:8088/t/${TOKEN}${path}`, input, wait });

async function context(browser, viewer) {
  const ctx = await browser.newContext();
  await ctx.addCookies([{ name: 'viewer', value: viewer, url: BASE }]);
  return ctx;
}

(async () => {
  const phase = process.argv[2];
  fs.mkdirSync(SHOTS, { recursive: true });
  const browser = await chromium.launch();

  if (phase === 'watch') {
    const page = await (await context(browser, 'owner')).newPage();
    await page.goto(`${T}/tty/`);
    const started = Date.now();
    const r = await ttyd(page, '/tty/ws', null, Number(process.argv[3] || 60000));
    console.log(`WATCH  ${r.state} after ${Date.now() - started} ms`);
    await browser.close();
    return;
  }

  const owner = await context(browser, 'owner');
  const page = await owner.newPage();

  // The terminal page and a keystroke round trip.
  let res = await page.goto(`${T}/tty/`);
  check('owner: the terminal page loads', res.status() === 200, `status ${res.status()}`);
  await page.waitForSelector('.xterm', { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1500);
  await page.keyboard.type('echo page-$((6*7))-typed');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${SHOTS}/${phase}-tty-page.png` });
  const echo = await ttyd(page, '/tty/ws', 'echo e2e-$((6*7))-ok\r', 3000);
  check('owner: keystrokes reach the shell and the output comes back', echo.out.includes('e2e-42-ok'), echo.state);

  if (phase === 'main') {
    // A second viewer: the read-only terminal, and none of the owner-only surfaces.
    const guest = await context(browser, 'guest');
    const gp = await guest.newPage();
    res = await gp.goto(`${T}/view/`);
    check('guest: the read-only terminal page loads', res.status() === 200, `status ${res.status()}`);
    await gp.waitForTimeout(1500);
    await gp.screenshot({ path: `${SHOTS}/${phase}-view-page.png` });
    const view = await ttyd(gp, '/view/ws', '0touch /tmp/view-wrote\r', 2500);
    check('guest: the read-only terminal streams the session', view.out.length > 0, view.state);
    const tty = await ttyd(page, '/tty/ws', 'ls /tmp/view-wrote 2>&1; echo done-$((1+1))\r', 2500);
    check('guest: typing into the read-only terminal changes nothing', tty.out.includes('No such file') && tty.out.includes('done-2'));
    for (const surface of ['tty', 'ide', 'upload']) {
      const r = await guest.request.get(`${T}/${surface}/`);
      check(`guest: ${surface} is refused`, r.status() === 403, `status ${r.status()}`);
    }
    const files = await guest.request.get(`${T}/fs/health`);
    check('guest: the file panel is served', files.status() === 200, `status ${files.status()}`);

    // The IDE, with its connection token, unstripped under /t/<token>/ide.
    res = await page.goto(`${T}/ide/?tkn=e2etoken&folder=/workspace&skipWelcome=true`);
    check('owner: the IDE loads', res.status() === 200, `status ${res.status()}`);
    await page.waitForTimeout(6000);
    await page.screenshot({ path: `${SHOTS}/${phase}-ide.png` });

    // An upload, as the terminal's paste does.
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
    const up = await owner.request.post(`${T}/upload`, { data: png, headers: { 'Content-Type': 'image/png' } });
    const body = await up.text();
    check('owner: an upload is stored', up.status() === 200 && body.includes('/'), `status ${up.status()} ${body.slice(0, 80)}`);

    // Nothing without a viewer.
    const anon = await browser.newContext();
    const a = await anon.request.get(`${T}/tty/`);
    check('no viewer: refused by terminal-auth before the relay', a.status() === 401, `status ${a.status()}`);
    const stranger = await owner.request.get(`${BASE}/t/ffffffffffffffffffffffffffffffff/tty/`);
    check('a token the platform does not know is 404', stranger.status() === 404, `status ${stranger.status()}`);
  }

  await browser.close();
  console.log(failed ? `${failed} FAILED` : 'ALL PASSED');
  process.exit(failed ? 1 : 0);
})();
