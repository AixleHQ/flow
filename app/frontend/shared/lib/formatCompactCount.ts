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
export function formatCompactCount(n: number, { thousandsSuffix = 'k' } = {}): string {
  let unit = UNITS.findIndex(({ size }) => n >= size);
  if (unit === -1) return String(n);
  if (unit > 0 && Number((n / UNITS[unit].size).toFixed(1)) >= 1000) unit--;
  const { size, suffix } = UNITS[unit];
  return `${(n / size).toFixed(1)}${suffix === 'k' ? thousandsSuffix : suffix}`;
}
