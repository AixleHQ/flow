/**
 * Number and duration formatting for the Sessions & Runs surfaces.
 *
 * These four functions had four near-identical copies (sessions list, runs
 * list, run detail, session detail) that had already drifted — one printed `—`
 * for a zero cost and another printed `$0.00`. Values are Geist-Mono-adjacent
 * data, so they are always rendered in the mono face; the labels beside them
 * are not.
 */

/** `228700` → `228.7k`. Zero reads as an em dash, not `0`. */
export function formatTokens(n: number | null | undefined): string {
  if (!n || n === 0) return '—';
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(n);
}

/** Cents → `$4.78`. Zero reads as an em dash. */
export function formatCost(cents: number | null | undefined): string {
  if (!cents || cents === 0) return '—';
  return `$${(cents / 100).toFixed(2)}`;
}

/**
 * Cost emphasis, three steps: quiet under $1, primary text to $5, amber above.
 * Never green — green means success and nothing else in this system.
 */
export function costColor(cents: number | null | undefined): string | undefined {
  if (!cents || cents === 0) return undefined;
  if (cents <= 100) return undefined;
  if (cents <= 500) return 'var(--app-text-primary)';
  return 'var(--app-warning-fg)';
}

const LIVE_STATES = new Set(['running', 'ready', 'in_progress', 'waiting_input', 'paused', 'pending', 'not_started']);

/**
 * Elapsed time between two timestamps. An unfinished record only ticks against
 * `now` while it is genuinely still live — a cancelled run has a start and no
 * end, and counting to now rendered "8487m 25s".
 */
export function formatDuration(
  startedAt: string | null | undefined,
  finishedAt: string | null | undefined,
  state?: string | null,
  now: number = Date.now(),
): string {
  if (!startedAt) return '—';
  if (!finishedAt && state != null && !LIVE_STATES.has(state)) return '—';
  const start = new Date(startedAt).getTime();
  const end = finishedAt ? new Date(finishedAt).getTime() : now;
  const seconds = Math.max(0, Math.round((end - start) / 1000));
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

/** `1536` → `1.5 KB`. */
export function formatFileSize(bytes: number | null | undefined): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * Model identifiers arrive as full inference-profile ARNs or region-prefixed
 * ids. Printed raw they filled the column with
 * `arn:aws:bedrock:us-east-1:541894707537:application-inference-profi…` — all
 * prefix, no model. Keep the part that identifies the model; the full string
 * belongs in a tooltip.
 */
export function shortModelName(id: string): string {
  let name = id.includes('/') ? (id.split('/').pop() ?? id) : id;
  name = name.replace(/^(us|eu|apac|global)\./i, '');
  name = name.replace(/^(anthropic|openai|google|meta)\./i, '');
  name = name.replace(/-v\d+:\d+$/, '');
  name = name.replace(/-(\d{8})$/, '');
  return name;
}
