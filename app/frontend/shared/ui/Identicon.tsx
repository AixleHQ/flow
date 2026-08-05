import { Box } from '@mantine/core';

interface IdenticonProps {
  /** Deterministic input — same seed always renders the same pattern. */
  seed: string;
  size?: number;
}

function hashString(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * Deterministic 5x5 monochrome identicon, mirrored left-right so the pattern
 * always reads symmetric (only the left 3 columns are derived from the hash;
 * the right 2 mirror them). Used as the project thumbnail in place of a plain
 * letter avatar — purely decorative, so it's `aria-hidden`.
 */
export function Identicon({ seed, size = 24 }: IdenticonProps) {
  const hash = hashString(seed);
  const cells: boolean[] = [];
  for (let row = 0; row < 5; row += 1) {
    for (let col = 0; col < 5; col += 1) {
      const mirroredCol = col < 3 ? col : 4 - col;
      cells.push(((hash >> (row * 3 + mirroredCol)) & 1) === 1);
    }
  }

  return (
    <Box
      aria-hidden="true"
      style={{
        width: size,
        height: size,
        display: 'grid',
        gridTemplateColumns: 'repeat(5, 1fr)',
        gridTemplateRows: 'repeat(5, 1fr)',
        gap: 1,
      }}
    >
      {cells.map((on, i) => (
        <span key={i} style={{ borderRadius: 1, background: on ? 'var(--app-text-tertiary)' : 'transparent' }} />
      ))}
    </Box>
  );
}
