import { formatCompactCount } from 'shared/lib/formatCompactCount';

export function formatCostCents(cents: number): string {
  const d = (cents ?? 0) / 100;
  if (d >= 1000) return `$${(d / 1000).toFixed(1)}k`;
  return `$${d.toFixed(2)}`;
}

export function formatTokens(n: number): string {
  if (!n) return '0';
  return formatCompactCount(n);
}
