export type TerminalKeyAction = { type: 'copy' } | { type: 'paste' } | { type: 'send'; data: string } | null;

type KeyLike = Pick<KeyboardEvent, 'key' | 'code' | 'ctrlKey' | 'shiftKey' | 'altKey' | 'metaKey'>;

// What iTerm and Terminal.app send for Cmd+←/→: readline's start and end of line,
// which is what the agent CLIs' prompts understand. xterm.js sends nothing for them.
const MAC_LINE_KEYS: Record<string, string> = { ArrowLeft: '\x01', ArrowRight: '\x05' };

// ESC CR, which xterm.js sends for Alt+Enter: Claude Code, Codex and Gemini CLI break
// the prompt's line on it. xterm.js sends Shift+, Ctrl+ and Cmd+Enter as a bare CR,
// indistinguishable from Enter, so they would submit the prompt instead.
const NEWLINE = '\x1b\r';

// Off the Mac the Meta key is Windows', and Win+Enter belongs to the OS.
function breaksLine(event: KeyLike, isMac: boolean): boolean {
  if (event.key !== 'Enter' || event.altKey) return false;
  if (event.metaKey) return isMac;
  return event.shiftKey || event.ctrlKey;
}

/**
 * Keys the browser terminal handles itself instead of xterm.js's defaults.
 *
 * Everywhere: Shift+Enter and Ctrl+Enter break the line, as Alt+Enter does.
 *
 * On the Mac: Cmd+Enter breaks the line too, and Cmd+←/→ go to the start or end of it.
 *
 * Elsewhere, clipboard keys as Windows Terminal and VS Code bind them. xterm.js
 * turns Ctrl+C and Ctrl+V into ^C and ^V, and ^V is Claude Code's "paste an image
 * from the system clipboard" — a clipboard the container does not have. So Ctrl+C
 * copies only while there is a selection (otherwise it still interrupts),
 * Ctrl+Shift+C and Ctrl+Insert copy, and Ctrl+V, Ctrl+Shift+V and Shift+Insert are
 * left to the browser's own paste. On the Mac, Cmd+C/Cmd+V never reach the CLI.
 */
export function terminalKeyAction(
  event: KeyLike,
  { isMac, hasSelection }: { isMac: boolean; hasSelection: boolean },
): TerminalKeyAction {
  if (breaksLine(event, isMac)) return { type: 'send', data: NEWLINE };

  if (isMac) {
    const line = MAC_LINE_KEYS[event.key];
    if (line && event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey)
      return { type: 'send', data: line };
    return null;
  }
  if (event.altKey || event.metaKey) return null;

  const letter = event.code === 'KeyC' ? 'c' : event.code === 'KeyV' ? 'v' : event.key.toLowerCase();
  const insert = event.key === 'Insert';

  if (event.ctrlKey && !event.shiftKey && letter === 'c') return hasSelection ? { type: 'copy' } : null;
  if (event.ctrlKey && event.shiftKey && letter === 'c') return { type: 'copy' };
  if (event.ctrlKey && !event.shiftKey && insert) return { type: 'copy' };
  if (event.ctrlKey && letter === 'v') return { type: 'paste' };
  if (event.shiftKey && !event.ctrlKey && insert) return { type: 'paste' };
  return null;
}

type NavigatorWithUaData = Navigator & { userAgentData?: { platform?: string } };

// userAgentData first: navigator.platform is deprecated and freezes or lies under
// user-agent overrides, while Chromium keeps userAgentData honest.
export function isMacPlatform(nav: NavigatorWithUaData = navigator): boolean {
  return /mac|iphone|ipad|ios/i.test(nav.userAgentData?.platform || nav.platform);
}
