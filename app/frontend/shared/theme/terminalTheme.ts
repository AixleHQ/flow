import type { ITheme } from '@xterm/xterm';

export type TerminalScheme = 'light' | 'dark';

// Dark keeps xterm's own ANSI palette; only the background is ours.
const DARK: ITheme = { background: '#000000' };

// GitHub Light's terminal palette, so agent output stays readable on white.
const LIGHT: ITheme = {
  background: '#ffffff',
  foreground: '#1f2328',
  cursor: '#0969da',
  cursorAccent: '#ffffff',
  selectionBackground: 'rgba(9, 105, 218, 0.25)',
  black: '#24292f',
  red: '#cf222e',
  green: '#116329',
  yellow: '#4d2d00',
  blue: '#0969da',
  magenta: '#8250df',
  cyan: '#1b7c83',
  white: '#6e7781',
  brightBlack: '#57606a',
  brightRed: '#a40e26',
  brightGreen: '#1a7f37',
  brightYellow: '#633c01',
  brightBlue: '#218bff',
  brightMagenta: '#a475f9',
  brightCyan: '#3192aa',
  brightWhite: '#8c959f',
};

export function terminalTheme(scheme: TerminalScheme): ITheme {
  return scheme === 'light' ? LIGHT : DARK;
}

/**
 * Mode 2031: an app that sets it is told the terminal's theme, both when it asks
 * (`CSI ? 996 n`) and whenever it changes. tmux (3.6+) sets it on this terminal
 * and forwards the report only to panes that set it themselves — Claude Code in
 * its "Auto" theme does. xterm.js knows nothing of the mode, so the page answers.
 */
export const THEME_REPORT_MODE = 2031;
export const THEME_QUERY = 996;

export function themeReport(scheme: TerminalScheme): string {
  return scheme === 'light' ? '\x1b[?997;2n' : '\x1b[?997;1n';
}
