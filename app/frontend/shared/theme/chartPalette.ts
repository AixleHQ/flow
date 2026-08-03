/**
 * Categorical chart palette.
 *
 * The analytics pages used to hardcode the Material Design 500 ramp
 * (`#2196f3`, `#9c27b0`, `#4caf50`, …) with no light-mode variant, which made
 * the one page a company admin visits to decide budget look like a generic
 * dashboard rather than this product. These resolve to the scheme-aware
 * `--app-chart-*` tokens defined in mantineTheme.ts, anchored on the brand.
 *
 * Recharts renders real SVG, so `var()` resolves in `fill` / `stroke` /
 * `stopColor` exactly as it does in CSS.
 */
export const CHART_SERIES = [
  'var(--app-chart-1)',
  'var(--app-chart-2)',
  'var(--app-chart-3)',
  'var(--app-chart-4)',
  'var(--app-chart-5)',
  'var(--app-chart-6)',
  'var(--app-chart-7)',
] as const;

/** Series color by index, wrapping around the ramp. */
export const chartColor = (index: number): string => CHART_SERIES[index % CHART_SERIES.length];

/** Semantic single-series colors, for charts that measure one known quantity. */
export const CHART_COST = 'var(--app-chart-1)';
export const CHART_TOKENS = 'var(--app-chart-6)';
export const CHART_SESSIONS = 'var(--app-chart-2)';
