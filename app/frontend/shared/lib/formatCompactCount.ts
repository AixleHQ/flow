const UNITS = [
  { size: 1e12, suffix: 'T' },
  { size: 1e9, suffix: 'B' },
  { size: 1e6, suffix: 'M' },
  { size: 1e3, suffix: 'k' },
];

/**
 * `228700` → `228.7k`, `1069700000` → `1.1B`. A value that rounds up to 1000 of
 * one unit is shown in the next one: `999950` → `1.0M`, not `1000.0k`.
 */
export function formatCompactCount(n: number): string {
  const count = Math.round(n);
  let unit = UNITS.findIndex(({ size }) => count >= size);
  if (unit === -1) return String(count);
  if (unit > 0 && Number((count / UNITS[unit].size).toFixed(1)) >= 1000) unit--;
  const { size, suffix } = UNITS[unit];
  return `${(count / size).toFixed(1)}${suffix}`;
}
