import { Button, Group, Loader, Text } from '@mantine/core';
import { type HotkeyItem, getHotkeyHandler } from '@mantine/hooks';
import type { Terminal } from '@xterm/xterm';
import { useEffect, useRef, useState } from 'react';

import { stripContainerTicket } from 'shared/lib/containerTicket';
import { findHardWrappedLink } from 'shared/lib/hardWrappedLink';
import { TtydConnection, type TtydStatus } from 'shared/lib/ttydConnection';
import { TERMINAL_BG } from 'shared/theme/vendorColors';

import classes from './LiveTerminal.module.css';

interface LiveTerminalProps {
  /** ttyd's websocket endpoint, container pass included. */
  url: string;
  /** Show the stream without sending keystrokes — someone else's session. */
  readOnly?: boolean;
  /** Accessible name; a read-only terminal is named for being someone else's. */
  label?: string;
  /**
   * App shortcuts that win over the CLI while the terminal has focus. Keep this to
   * combinations no agent CLI binds: on Linux `mod` is Ctrl, and Ctrl+B is tmux's prefix.
   */
  hotkeys?: HotkeyItem[];
}

function cssToken(name: string): string | undefined {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || undefined;
}

async function loadXterm() {
  const [{ Terminal }, { FitAddon }, { WebglAddon }, { Unicode11Addon }, { ClipboardAddon }] = await Promise.all([
    import('@xterm/xterm'),
    import('@xterm/addon-fit'),
    import('@xterm/addon-webgl'),
    import('@xterm/addon-unicode11'),
    import('@xterm/addon-clipboard'),
    import('@xterm/xterm/css/xterm.css'),
  ]);
  return { Terminal, FitAddon, WebglAddon, Unicode11Addon, ClipboardAddon };
}

// Joins the URL a CLI hard-wrapped across rows; see findHardWrappedLink.
function registerWrappedLinks(term: Terminal) {
  return term.registerLinkProvider({
    provideLinks(line, callback) {
      const buffer = term.buffer.active;
      const rowAt = (n: number) => buffer.getLine(n - 1)?.translateToString(true) ?? '';
      const link = findHardWrappedLink(line, rowAt, buffer.length);
      if (!link) {
        callback(undefined);
        return;
      }
      callback([
        {
          range: { start: link.start, end: link.end },
          text: link.url,
          decorations: { underline: true, pointerCursor: true },
          activate: (_event, text) => window.open(text, '_blank', 'noopener,noreferrer'),
        },
      ]);
    },
  });
}

/**
 * The agent's terminal, rendered in the page with xterm.js and wired straight to the
 * container's ttyd websocket — no iframe, so the page's theme, focus and shortcuts
 * reach it. tmux inside the container keeps the session; a reconnect just reattaches.
 */
export function LiveTerminal({ url, readOnly = false, label = 'Terminal', hotkeys }: LiveTerminalProps) {
  const screenRef = useRef<HTMLDivElement>(null);
  const connectionRef = useRef<TtydConnection | null>(null);
  const urlRef = useRef(url);
  const hotkeysRef = useRef(hotkeys);
  const [status, setStatus] = useState<TtydStatus>('connecting');
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    urlRef.current = url;
    hotkeysRef.current = hotkeys;
  });

  // Each serialization of the page mints the URL a fresh pass; only a new route
  // is a different terminal. The latest URL is read at every (re)connect.
  const route = stripContainerTicket(url);

  useEffect(() => {
    let disposed = false;
    const cleanups: (() => void)[] = [];
    const track = (disposable: { dispose(): void }) => cleanups.push(() => disposable.dispose());

    async function mount() {
      const xterm = await loadXterm();
      const el = screenRef.current;
      if (disposed || !el) return;

      const term = new xterm.Terminal({
        allowProposedApi: true,
        cursorBlink: !readOnly,
        disableStdin: readOnly,
        fontFamily: cssToken('--app-font-mono') ?? 'monospace',
        fontSize: 14,
        scrollback: 10_000,
        theme: { background: cssToken('--app-terminal-bg') ?? TERMINAL_BG },
      });
      track(term);

      const fit = new xterm.FitAddon();
      term.loadAddon(fit);
      term.loadAddon(new xterm.Unicode11Addon());
      term.unicode.activeVersion = '11';
      // OSC 52: the CLIs' own "copy" (Claude Code's `c` on the login URL) through tmux passthrough.
      term.loadAddon(new xterm.ClipboardAddon());
      term.open(el);

      try {
        const webgl = new xterm.WebglAddon();
        webgl.onContextLoss(() => webgl.dispose());
        term.loadAddon(webgl);
      } catch {
        // No WebGL2 (blocked, headless, old GPU): xterm keeps its DOM renderer.
      }

      track(registerWrappedLinks(term));
      // Copy on select, as ttyd's client did: on Linux and Windows Ctrl+C belongs to the CLI.
      track(
        term.onSelectionChange(() => {
          const selection = term.getSelection();
          if (selection) void navigator.clipboard?.writeText(selection).catch(() => {});
        }),
      );
      term.attachCustomKeyEventHandler((event) => {
        const bindings = hotkeysRef.current;
        if (!bindings?.length || event.type !== 'keydown') return true;
        getHotkeyHandler(bindings)(event);
        return !event.defaultPrevented;
      });

      const connection = new TtydConnection({
        url: () => urlRef.current,
        sink: {
          get cols() {
            return term.cols;
          },
          get rows() {
            return term.rows;
          },
          write: (data, done) => term.write(data, done),
          reset: () => term.reset(),
        },
        onStatus: (next) => {
          if (disposed) return;
          setStatus(next);
          if (next === 'open' && !readOnly) term.focus();
        },
      });
      connectionRef.current = connection;
      cleanups.push(() => {
        connection.dispose();
        connectionRef.current = null;
      });

      if (!readOnly) {
        track(term.onData((data) => connection.input(data)));
        track(term.onBinary((data) => connection.input(Uint8Array.from(data, (c) => c.charCodeAt(0)))));
      }
      track(term.onResize(({ cols, rows }) => connection.resize(cols, rows)));

      let frame = 0;
      const refit = () => {
        cancelAnimationFrame(frame);
        frame = requestAnimationFrame(() => fit.fit());
      };
      const observer = new ResizeObserver(refit);
      observer.observe(el);
      cleanups.push(() => {
        observer.disconnect();
        cancelAnimationFrame(frame);
      });

      fit.fit();
      connection.connect();
    }

    setStatus('connecting');
    setFailed(false);
    mount().catch(() => {
      if (!disposed) setFailed(true);
    });

    return () => {
      disposed = true;
      cleanups.reverse().forEach((cleanup) => cleanup());
    };
  }, [route, readOnly]);

  return (
    <div
      className={classes.root}
      role="group"
      aria-label={readOnly ? "Read-only view of another user's session" : label}
      data-status={status}
    >
      <div ref={screenRef} className={classes.screen} />
      {failed ? (
        <div className={classes.overlay}>
          <Text size="sm" c="var(--app-danger-fg)">
            The terminal could not start in this browser.
          </Text>
        </div>
      ) : status === 'connecting' ? (
        <div className={classes.overlay}>
          <Loader size="md" />
          <Text size="sm" c="dimmed">
            Connecting to terminal…
          </Text>
        </div>
      ) : status === 'reconnecting' ? (
        <Group gap={6} className={classes.overlayBanner}>
          <Loader size="xs" />
          <Text size="xs" c="dimmed">
            Reconnecting…
          </Text>
        </Group>
      ) : status === 'closed' ? (
        <Group gap={8} className={classes.overlayBanner}>
          <Text size="xs" c="dimmed">
            Disconnected
          </Text>
          <Button size="compact-xs" variant="light" onClick={() => connectionRef.current?.reconnect()}>
            Reconnect
          </Button>
        </Group>
      ) : null}
    </div>
  );
}
