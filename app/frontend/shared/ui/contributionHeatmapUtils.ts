export function intensityLevel(count: number): number {
  if (!Number.isFinite(count) || count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  if (count <= 9) return 3;
  return 4;
}
