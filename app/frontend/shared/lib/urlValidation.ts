export function isValidHttpsUrl(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed) return false;
  try {
    return new URL(trimmed).protocol === 'https:';
  } catch {
    return false;
  }
}
