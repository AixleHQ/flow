/**
 * The wire protocol of ttyd's `/ws` endpoint, as spoken by its own bundled client
 * (html/src/components/terminal/xterm/index.ts at the TTYD_VERSION pinned in
 * docker/base/Dockerfile). Every frame is binary; its first byte names the command.
 */

export const TTYD_SUBPROTOCOL = 'tty';

const INPUT = '0'.charCodeAt(0);
const RESIZE = '1'.charCodeAt(0);
const PAUSE = '2'.charCodeAt(0);
const RESUME = '3'.charCodeAt(0);

const OUTPUT = '0'.charCodeAt(0);
const SET_WINDOW_TITLE = '1'.charCodeAt(0);
const SET_PREFERENCES = '2'.charCodeAt(0);

export type TtydFrame =
  | { type: 'output'; data: Uint8Array }
  | { type: 'title'; title: string }
  | { type: 'preferences' }
  | { type: 'unknown' };

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function withCommand(command: number, body: Uint8Array): Uint8Array<ArrayBuffer> {
  const frame = new Uint8Array(body.length + 1);
  frame[0] = command;
  frame.set(body, 1);
  return frame;
}

/** The first frame after the socket opens: ttyd spawns the command at this size. */
export function encodeHandshake(cols: number, rows: number): Uint8Array<ArrayBuffer> {
  return encoder.encode(JSON.stringify({ AuthToken: '', columns: cols, rows }));
}

/** Keystrokes as xterm reports them: `onData` gives text, `onBinary` gives byte strings. */
export function encodeInput(data: string | Uint8Array): Uint8Array<ArrayBuffer> {
  return withCommand(INPUT, typeof data === 'string' ? encoder.encode(data) : data);
}

export function encodeResize(cols: number, rows: number): Uint8Array<ArrayBuffer> {
  return withCommand(RESIZE, encoder.encode(JSON.stringify({ columns: cols, rows })));
}

export const PAUSE_FRAME = Uint8Array.of(PAUSE);
export const RESUME_FRAME = Uint8Array.of(RESUME);

export function decodeFrame(raw: ArrayBuffer): TtydFrame {
  const bytes = new Uint8Array(raw);
  if (bytes.length === 0) return { type: 'unknown' };
  const body = bytes.subarray(1);
  switch (bytes[0]) {
    case OUTPUT:
      return { type: 'output', data: body };
    case SET_WINDOW_TITLE:
      return { type: 'title', title: decoder.decode(body) };
    case SET_PREFERENCES:
      return { type: 'preferences' };
    default:
      return { type: 'unknown' };
  }
}
