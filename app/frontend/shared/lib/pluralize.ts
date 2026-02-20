// Pluralize utility for shared use
export function pluralize(count: number | null | undefined, singular: string, plural: string) {
  if (count === null || count === undefined) return `—`;
  return `${count} ${count === 1 ? singular : plural}`;
}
