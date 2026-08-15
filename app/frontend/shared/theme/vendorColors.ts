/**
 * The one legitimate home for literal colors outside the theme.
 *
 * These are other companies' brand marks, not our palette: the Google "G" and
 * the agent-runtime identity swatches. A brand color is not a design token — it
 * cannot shift with our color scheme and it must not be "improved" for
 * contrast, so it does not belong in the `--app-*` contract. Collecting them
 * here is what lets the `no-restricted-syntax` hex rule stay hard everywhere
 * else (this directory is the rule's only ignore).
 *
 * Rules for using these: identity only — a swatch, a bar, an icon. Never as a
 * fill behind our own text, and never as the color of a primary action.
 */

/** Agent-runtime identity swatches, keyed by `agentType`. */
export const AGENT_BRAND_COLORS: Record<string, string> = {
  claude_code: '#d97706',
  cursor_cli: '#7c3aed',
  codex: '#10a37f',
  gemini_cli: '#3b82f6',
  // xAI's mark is monochrome — black on white, white on black — so there is no
  // chromatic brand value to carry here. A neutral slate is the identity: it reads
  // as the monochrome brand and stays visible on both light and dark surfaces,
  // which a literal #000 swatch would not.
  grok: '#71717a',
};

/** Google's four-color mark, for the "Sign in with Google" button only. */
export const GOOGLE_BRAND = {
  blue: '#4285F4',
  green: '#34A853',
  yellow: '#FBBC05',
  red: '#EA4335',
} as const;

/**
 * Terminal surfaces render an xterm.js canvas that is black by contract, not a
 * themed surface — the agent's own ANSI colors are drawn against it.
 */
export const TERMINAL_BG = '#000';

/**
 * Backgrounds the vendor logo tiles need to stay legible: the Codex mark is dark
 * ink and wants white behind it, the Gemini mark is light and wants near-black.
 * Fixed by the artwork, not by our scheme.
 */
export const LOGO_TILE_BG = {
  light: '#ffffff',
  dark: '#14100e',
} as const;
