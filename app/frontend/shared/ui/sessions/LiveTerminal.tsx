import { Button, Group, Loader, Text, useComputedColorScheme } from '@mantine/core';
import { type HotkeyItem, getHotkeyHandler } from '@mantine/hooks';
import type { Terminal } from '@xterm/xterm';
import { type ClipboardEvent, type DragEvent, useCallback, useEffect, useRef, useState } from 'react';

import { stripContainerTicket } from 'shared/lib/containerTicket';
import { findHardWrappedLink } from 'shared/lib/hardWrappedLink';
import { pastedImages, uploadImage } from 'shared/lib/imagePaste';
import { isMacPlatform, terminalKeyAction } from 'shared/lib/terminalKeys';
import { TtydConnection, type TtydStatus } from 'shared/lib/ttydConnection';
import {
  THEME_QUERY,
  THEME_REPORT_MODE,
  type TerminalScheme,
  terminalTheme,
  themeReport,
} from 'shared/theme/terminalTheme';

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
  /** Where a pasted or dropped image is stored in the container; without it images are ignored. */
  uploadUrl?: string | null;
}

type UploadState = { kind: 'idle' } | { kind: 'uploading' } | { kind: 'failed'; message: string };

const includesMode = (params: (number | number[])[], mode: number) => params.some((p) => p === mode);

// Inside tmux, Claude Code answers a theme report by asking for the background
// through a passthrough it gives 2 s to reply, then asks tmux itself, and does
// not repaint once it has. Resizing the pane by a column and back makes it. Input
// does not: an empty paste is ignored, and a focus event makes it summarise the
// session as if the user had been away.
const THEME_REPAINT_DELAY_MS = 2500;
const RESIZE_BACK_MS = 50;

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
export function LiveTerminal({ url, readOnly = false, label = 'Terminal', hotkeys, uploadUrl }: LiveTerminalProps) {
  const screenRef = useRef<HTMLDivElement>(null);
  const connectionRef = useRef<TtydConnection | null>(null);
  const urlRef = useRef(url);
  const hotkeysRef = useRef(hotkeys);
  const uploadUrlRef = useRef(uploadUrl);
  const termRef = useRef<Terminal | null>(null);
  // Set while tmux has asked to be told about theme changes (mode 2031).
  const reportsThemeRef = useRef(false);
  const scheme: TerminalScheme = useComputedColorScheme('dark');
  const schemeRef = useRef(scheme);
  const [status, setStatus] = useState<TtydStatus>('connecting');
  const [failed, setFailed] = useState(false);
  const [upload, setUpload] = useState<UploadState>({ kind: 'idle' });

  useEffect(() => {
    urlRef.current = url;
    hotkeysRef.current = hotkeys;
    uploadUrlRef.current = uploadUrl;
  });

  const repaintTimers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const scheduleRepaint = useCallback(() => {
    repaintTimers.current.forEach(clearTimeout);
    const nudge = setTimeout(() => {
      const term = termRef.current;
      if (!term) return;
      connectionRef.current?.resize(term.cols - 1, term.rows);
      const restore = setTimeout(() => connectionRef.current?.resize(term.cols, term.rows), RESIZE_BACK_MS);
      repaintTimers.current.push(restore);
    }, THEME_REPAINT_DELAY_MS);
    repaintTimers.current = [nudge];
  }, []);

  useEffect(() => () => repaintTimers.current.forEach(clearTimeout), []);

  useEffect(() => {
    schemeRef.current = scheme;
    const term = termRef.current;
    if (!term) return;
    term.options.theme = terminalTheme(scheme);
    // tmux answers by asking xterm for its background again, which is how it
    // learns the new theme before passing it on to the CLI.
    if (!reportsThemeRef.current || readOnly) return;
    connectionRef.current?.input(themeReport(scheme));
    scheduleRepaint();
  }, [scheme, readOnly, scheduleRepaint]);

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
        theme: terminalTheme(schemeRef.current),
      });
      track(term);
      termRef.current = term;
      cleanups.push(() => {
        termRef.current = null;
      });

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
      const isMac = isMacPlatform();
      term.attachCustomKeyEventHandler((event) => {
        const action = terminalKeyAction(event, { isMac, hasSelection: term.hasSelection() });
        if (action?.type === 'send') {
          event.preventDefault();
          if (event.type === 'keydown' && !readOnly) connectionRef.current?.input(action.data);
          return false;
        }
        if (action?.type === 'copy') {
          // Also keeps Ctrl+Shift+C from opening the browser's devtools.
          event.preventDefault();
          if (event.type === 'keydown' && term.hasSelection()) {
            void navigator.clipboard?.writeText(term.getSelection()).catch(() => {});
            term.clearSelection();
          }
          return false;
        }
        // Not handled and not prevented: the browser pastes, and xterm (or the image upload) takes it from there.
        if (action?.type === 'paste') return false;

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
          reset: () => {
            reportsThemeRef.current = false;
            term.reset();
          },
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

      track(
        term.parser.registerCsiHandler({ prefix: '?', final: 'h' }, (params) => {
          if (includesMode(params, THEME_REPORT_MODE)) reportsThemeRef.current = true;
          return false;
        }),
      );
      track(
        term.parser.registerCsiHandler({ prefix: '?', final: 'l' }, (params) => {
          if (includesMode(params, THEME_REPORT_MODE)) reportsThemeRef.current = false;
          return false;
        }),
      );
      track(
        term.parser.registerCsiHandler({ prefix: '?', final: 'n' }, (params) => {
          if (params[0] !== THEME_QUERY) return false;
          if (readOnly) return true;
          connection.input(themeReport(schemeRef.current));
          // tmux asks when a client attaches: the CLI learns the theme now, and
          // may have started without one.
          scheduleRepaint();
          return true;
        }),
      );

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
  }, [route, readOnly, scheduleRepaint]);

  async function pasteImages(images: File[]) {
    const target = uploadUrlRef.current;
    if (!target) return;
    setUpload({ kind: 'uploading' });
    try {
      for (const image of images) {
        const path = await uploadImage(target, image);
        // Pasted, not typed: Claude Code turns a pasted image path into an attachment.
        termRef.current?.paste(path);
      }
      setUpload({ kind: 'idle' });
    } catch (error) {
      setUpload({ kind: 'failed', message: error instanceof Error ? error.message : String(error) });
    }
    termRef.current?.focus();
  }

  const acceptsImages = !readOnly && Boolean(uploadUrl);

  // Capture phase, so xterm's own paste handler (which only reads text) never sees an image.
  function handlePaste(event: ClipboardEvent) {
    if (!acceptsImages) return;
    const images = pastedImages(event.clipboardData);
    if (images.length === 0) return;
    event.preventDefault();
    event.stopPropagation();
    void pasteImages(images);
  }

  function handleDragOver(event: DragEvent) {
    if (acceptsImages && event.dataTransfer.types.includes('Files')) event.preventDefault();
  }

  function handleDrop(event: DragEvent) {
    if (!acceptsImages) return;
    const images = pastedImages(event.dataTransfer);
    if (images.length === 0) return;
    event.preventDefault();
    void pasteImages(images);
  }

  return (
    <div
      className={classes.root}
      role="group"
      aria-label={readOnly ? "Read-only view of another user's session" : label}
      data-status={status}
      onPasteCapture={handlePaste}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
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
      ) : upload.kind === 'uploading' ? (
        <Group gap={6} className={classes.overlayBanner}>
          <Loader size="xs" />
          <Text size="xs" c="dimmed">
            Uploading image…
          </Text>
        </Group>
      ) : upload.kind === 'failed' ? (
        <Group gap={8} className={classes.overlayBanner} role="alert">
          <Text size="xs" c="var(--app-danger-fg)">
            {upload.message}
          </Text>
          <Button size="compact-xs" variant="subtle" onClick={() => setUpload({ kind: 'idle' })}>
            Dismiss
          </Button>
        </Group>
      ) : null}
    </div>
  );
}
