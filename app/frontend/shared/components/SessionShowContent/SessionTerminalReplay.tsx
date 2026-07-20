import { Box, Loader, Text, useComputedColorScheme } from '@mantine/core';
import { useEffect, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';

import classes from './SessionTerminalReplay.module.css';

/**
 * Read-only replay of a finished session's captured terminal log. Fetches the
 * raw ANSI bytes from `logUrl` (server already caps to the tail) and renders
 * them into xterm.js, preserving the original colors/markup. Static dump (no
 * time-based playback); input-disabled. xterm is lazy-imported so it stays out
 * of the main bundle.
 */

type Status = 'loading' | 'ready' | 'empty' | 'error';

interface Props {
  logUrl: string;
}

// Read the app's terminal colors from the --app-* theme tokens (light/dark aware).
function readTerminalTheme() {
  const style = getComputedStyle(document.documentElement);
  const token = (name: string) => style.getPropertyValue(name).trim() || undefined;
  return {
    fontFamily: token('--app-font-mono') ?? 'monospace',
    theme: { background: token('--app-bg-deep'), foreground: token('--app-text-primary') },
  };
}

// eslint-disable-next-line no-control-regex
const ANSI = /\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_()][0-9A-Za-z]?/g;

// The captured stream was drawn at the agent pane's column width; TUI box-art
// only lines up if xterm renders at that same width. Infer it from the widest
// rendered line (ANSI stripped, \r segments split so overwrites don't inflate).
function detectCols(text: string): number {
  let cols = 0;
  for (const line of text.replace(ANSI, '').split('\n')) {
    for (const seg of line.split('\r')) {
      const len = [...seg].length;
      if (len > cols) cols = len;
    }
  }
  return Math.min(Math.max(cols || 80, 20), 400);
}

// Pick a font size so `cols` columns exactly fill the container width — this is
// what makes the box borders align and fit instead of wrapping/clipping. rows
// follow from the height; the rest of the session scrolls in the scrollback.
function computeLayout(text: string, el: HTMLElement) {
  const cols = detectCols(text);
  const width = (el.clientWidth || 700) - 16; // minus padding
  const height = (el.clientHeight || 420) - 16;
  const CHAR_W = 0.6; // monospace advance ≈ 0.6em
  const fontSize = Math.min(Math.max(Math.floor(width / (cols * CHAR_W)), 6), 14);
  const rows = Math.max(Math.floor(height / (fontSize * 1.25)), 4);
  return { cols, rows, fontSize };
}

export function SessionTerminalReplay({ logUrl }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const termRef = useRef<import('@xterm/xterm').Terminal | null>(null);
  const [status, setStatus] = useState<Status>('loading');
  const [truncated, setTruncated] = useState(false);
  const colorScheme = useComputedColorScheme('dark', { getInitialValueInEffect: true });

  // Load + render once per logUrl. colorScheme is intentionally NOT a dependency:
  // a theme toggle must not re-download the log or rebuild the terminal — the
  // separate effect below recolors in place.
  useEffect(() => {
    let disposed = false;
    let onResize: (() => void) | null = null;

    async function run() {
      try {
        const res = await apiFetch(logUrl);
        if (disposed) return;
        if (res.status === 404) {
          setStatus('empty');
          return;
        }
        if (!res.ok) {
          setStatus('error');
          return;
        }

        let text = await res.text();
        if (disposed) return;
        if (!text) {
          setStatus('empty');
          return;
        }

        const isTruncated = res.headers.get('X-Log-Truncated') === 'true';
        if (isTruncated) {
          // The server sent a byte-tail that may begin mid-line / mid-escape;
          // drop the partial first line so xterm never renders a broken sequence.
          const nl = text.indexOf('\n');
          if (nl >= 0) text = text.slice(nl + 1);
        }

        const { Terminal } = await import('@xterm/xterm');
        await import('@xterm/xterm/css/xterm.css');
        if (disposed || !containerRef.current) return;

        const el = containerRef.current;
        const { fontFamily, theme } = readTerminalTheme();
        const { cols, rows, fontSize } = computeLayout(text, el);
        const term = new Terminal({
          disableStdin: true,
          convertEol: false, // raw PTY stream already contains \r\n
          scrollback: 100_000,
          cols,
          rows,
          fontSize,
          fontFamily,
          theme,
        });
        term.open(el);
        term.write(text);
        termRef.current = term;

        // On container resize keep the inferred column count; only rescale the
        // font (and rows) so the fixed-width box-art stays aligned and fitted.
        onResize = () => {
          const layout = computeLayout(text, el);
          term.options.fontSize = layout.fontSize;
          term.resize(cols, layout.rows);
        };
        window.addEventListener('resize', onResize);

        setTruncated(isTruncated);
        setStatus('ready');
      } catch {
        if (!disposed) setStatus('error');
      }
    }

    void run();

    return () => {
      disposed = true;
      if (onResize) window.removeEventListener('resize', onResize);
      termRef.current?.dispose();
      termRef.current = null;
    };
  }, [logUrl]);

  // Recolor in place when the app theme changes — no refetch, no rebuild.
  useEffect(() => {
    const term = termRef.current;
    if (!term) return;
    term.options.theme = readTerminalTheme().theme;
  }, [colorScheme]);

  if (status === 'empty') {
    return (
      <Text size="xs" c="dimmed" ta="center">
        No terminal output was captured for this session.
      </Text>
    );
  }
  if (status === 'error') {
    return (
      <Text size="xs" c="red" ta="center">
        Could not load the session terminal log.
      </Text>
    );
  }

  return (
    <Box w="100%">
      <Text size="xs" fw={600} c="dimmed" tt="uppercase" mb={4}>
        Session Terminal
      </Text>
      {truncated && (
        <Text size="xs" c="yellow" mb={4}>
          Log truncated — showing the most recent output.
        </Text>
      )}
      <Box className={classes.terminal} pos="relative">
        {status === 'loading' && (
          <Box className={classes.loaderOverlay}>
            <Loader size="sm" />
          </Box>
        )}
        <div ref={containerRef} className={classes.xterm} />
      </Box>
    </Box>
  );
}
