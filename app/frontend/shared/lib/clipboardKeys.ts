export type ClipboardKeyAction = 'copy' | 'paste' | null;

type KeyLike = Pick<KeyboardEvent, 'key' | 'code' | 'ctrlKey' | 'shiftKey' | 'altKey' | 'metaKey'>;

/**
 * Terminal clipboard keys off the Mac, as Windows Terminal and VS Code bind them.
 * xterm.js turns Ctrl+C and Ctrl+V into ^C and ^V, and ^V is Claude Code's "paste an
 * image from the system clipboard" — a clipboard the container does not have. So:
 * Ctrl+C copies only while there is a selection (otherwise it still interrupts),
 * Ctrl+Shift+C and Ctrl+Insert copy, and Ctrl+V, Ctrl+Shift+V and Shift+Insert are
 * left to the browser's own paste. On the Mac, Cmd+C/Cmd+V never reach the CLI.
 */
export function clipboardKeyAction(
  event: KeyLike,
  { isMac, hasSelection }: { isMac: boolean; hasSelection: boolean },
): ClipboardKeyAction {
  if (isMac || event.altKey || event.metaKey) return null;

  const letter = event.code === 'KeyC' ? 'c' : event.code === 'KeyV' ? 'v' : event.key.toLowerCase();
  const insert = event.key === 'Insert';

  if (event.ctrlKey && !event.shiftKey && letter === 'c') return hasSelection ? 'copy' : null;
  if (event.ctrlKey && event.shiftKey && letter === 'c') return 'copy';
  if (event.ctrlKey && !event.shiftKey && insert) return 'copy';
  if (event.ctrlKey && letter === 'v') return 'paste';
  if (event.shiftKey && !event.ctrlKey && insert) return 'paste';
  return null;
}

export function isMacPlatform(): boolean {
  return /Mac|iPhone|iPad/.test(navigator.platform);
}
