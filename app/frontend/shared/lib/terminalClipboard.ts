import type { IClipboardProvider } from '@xterm/addon-clipboard';

/**
 * Where a terminal's OSC 52 sequences reach the browser clipboard. Output is the
 * agent's, so it may put text on the viewer's clipboard but never read it: a read
 * would type the viewer's clipboard into the session. The write lands only while
 * the page has focus, since the browser refuses it otherwise, and never for a
 * session the viewer is only watching.
 */
export const terminalClipboardProvider = ({ readOnly }: { readOnly: boolean }): IClipboardProvider => ({
  readText: () => '',
  writeText: async (selection, text) => {
    if (readOnly || (selection as string) !== 'c' || !document.hasFocus()) return;
    await navigator.clipboard?.writeText(text).catch(() => {});
  },
});
