// Patches ttyd's xterm client to fix copying a hard-wrapped URL.
// xterm.js bug #5412: WebLinksAddon only stitches soft-wrapped rows (isWrapped),
// but tmux + Claude Code emit HARD newlines, so a wrapped OAuth URL is seen as
// separate per-row segments — clicking/selecting yields only a fragment.
// Fix: replace WebLinksAddon with a custom link provider that rejoins consecutive
// "URL-piece" rows (non-empty, no internal spaces) IGNORING isWrapped, and on click
// writes the FULL url to the browser clipboard (one-click, intuitive).
const fs = require('fs');
const p = 'html/src/components/terminal/xterm/index.ts';
let s = fs.readFileSync(p, 'utf8');

// Remove the stock WebLinksAddon entirely (we replace it with our own provider).
const subs = [
    [`import { WebLinksAddon } from '@xterm/addon-web-links';\n`, ''],
    [`    private webLinksAddon = new WebLinksAddon();\n`, ''],
    [`const { terminal, fitAddon, overlayAddon, clipboardAddon, webLinksAddon } = this;`,
     `const { terminal, fitAddon, overlayAddon, clipboardAddon } = this;`],
];
for (const [from, to] of subs) {
    if (!s.includes(from)) { console.error('[patch-ttyd] sub anchor not found:', JSON.stringify(from.slice(0, 50))); process.exit(1); }
    s = s.replace(from, to);
}

const anchor = `        terminal.loadAddon(clipboardAddon);
        terminal.loadAddon(webLinksAddon);

        terminal.open(parent);
        fitAddon.fit();`;

const replacement = `        terminal.loadAddon(clipboardAddon);

        terminal.open(parent);
        fitAddon.fit();

        // [aixle] Copy the FULL url on click, rejoining hard-wrapped rows.
        // Works around xterm.js #5412 (WebLinksAddon only stitches isWrapped rows;
        // tmux/Claude emit hard newlines). A "URL piece" row is non-empty with no
        // internal whitespace; consecutive pieces are concatenated and matched.
        const _isPiece = (str: string) => {
            const t = str.replace(/\\s+$/, '');
            return t.length > 0 && !/\\s/.test(t);
        };
        terminal.registerLinkProvider({
            provideLinks: (bufferLineNumber: number, callback) => {
                const buf = terminal.buffer.active;
                const get = (n: number) => {
                    const l = buf.getLine(n - 1);
                    return l ? l.translateToString(true) : '';
                };
                if (!_isPiece(get(bufferLineNumber))) {
                    callback(undefined);
                    return;
                }
                let start = bufferLineNumber;
                while (start > 1 && _isPiece(get(start - 1))) start--;
                let end = bufferLineNumber;
                while (end < buf.length && _isPiece(get(end + 1))) end++;
                let joined = '';
                for (let n = start; n <= end; n++) joined += get(n).trim();
                const m = joined.match(/https?:\\/\\/[^\\s]+/);
                if (!m) {
                    callback(undefined);
                    return;
                }
                const url = m[0];
                const range = { start: { x: 1, y: start }, end: { x: terminal.cols, y: end } };
                callback([
                    {
                        range,
                        text: url,
                        decorations: { underline: true, pointerCursor: true },
                        activate: (_e: MouseEvent, text: string) => {
                            // Open the FULL (rejoined) URL in a new browser tab. The
                            // click is a user gesture, so window.open is allowed even
                            // from the iframe. The user logs in there, then pastes the
                            // code back into the terminal.
                            window.open(text, '_blank', 'noopener,noreferrer');
                            overlayAddon.showOverlay('\\u2197 opening', 1000);
                        },
                    },
                ]);
            },
        });`;

if (!s.includes(anchor)) {
    console.error('[patch-ttyd] anchor not found — ttyd source layout changed');
    process.exit(1);
}
s = s.replace(anchor, replacement);
fs.writeFileSync(p, s);
console.log('[patch-ttyd] applied custom copy-full-url link provider');
