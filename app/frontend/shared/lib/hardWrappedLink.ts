export interface CellPosition {
  x: number;
  y: number;
}

export interface HardWrappedLink {
  url: string;
  start: CellPosition;
  end: CellPosition;
}

const URL_START = /https?:\/\//;
const URL_MATCH = /https?:\/\/\S+/;

// A continuation row of a hard-wrapped URL: non-empty, no whitespace inside.
function isPiece(row: string): boolean {
  const trimmed = row.trimEnd();
  return trimmed.length > 0 && !/\s/.test(trimmed);
}

/**
 * The URL under buffer row `line` (1-based, as xterm's link providers count), rejoined
 * across rows. xterm's WebLinksAddon only stitches soft-wrapped rows (xterm.js #5412),
 * and tmux plus the agent CLIs wrap a long login URL with hard newlines, so the stock
 * provider opens a fragment. The first row may carry prose before the URL (Cursor CLI
 * prints "…navigate to this link: https://…"); every row after it must be a bare piece.
 */
export function findHardWrappedLink(
  line: number,
  rowAt: (line: number) => string,
  lineCount: number,
): HardWrappedLink | null {
  const current = rowAt(line);
  if (!isPiece(current) && !URL_START.test(current)) return null;

  let start = line;
  while (start > 1) {
    const previous = rowAt(start - 1);
    if (isPiece(previous)) {
      start -= 1;
      continue;
    }
    if (URL_START.test(previous)) start -= 1;
    break;
  }
  let end = line;
  while (end < lineCount && isPiece(rowAt(end + 1))) end += 1;

  const rows: string[] = [];
  for (let n = start; n <= end; n += 1) rows.push(rowAt(n));
  const match = URL_MATCH.exec(rows.join(''));
  if (!match) return null;

  const urlStart = match.index;
  const urlLast = urlStart + match[0].length - 1;
  let startPos: CellPosition | null = null;
  let endPos: CellPosition | null = null;
  let offset = 0;
  for (let i = 0; i < rows.length; i += 1) {
    const rowEnd = offset + rows[i].length;
    if (urlStart >= offset && urlStart < rowEnd) startPos = { x: urlStart - offset + 1, y: start + i };
    if (urlLast >= offset && urlLast < rowEnd) endPos = { x: urlLast - offset + 1, y: start + i };
    offset = rowEnd;
  }
  // A bare word on the row above a URL joins the scan but is not part of the link.
  if (!startPos || !endPos || line < startPos.y || line > endPos.y) return null;
  return { url: match[0], start: startPos, end: endPos };
}
