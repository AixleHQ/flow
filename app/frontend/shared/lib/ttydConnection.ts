import {
  PAUSE_FRAME,
  RESUME_FRAME,
  TTYD_SUBPROTOCOL,
  decodeFrame,
  encodeHandshake,
  encodeInput,
  encodeResize,
} from './ttydProtocol';

/** The part of an xterm `Terminal` the connection drives. */
export interface TerminalSink {
  readonly cols: number;
  readonly rows: number;
  write(data: Uint8Array, done?: () => void): void;
  reset(): void;
}

export type TtydStatus = 'connecting' | 'open' | 'reconnecting' | 'closed';

type SocketLike = Pick<WebSocket, 'binaryType' | 'readyState' | 'send' | 'close' | 'addEventListener'>;

interface TtydConnectionOptions {
  /** Read on every (re)connect, so a reconnect carries the freshest container pass. */
  url: () => string;
  sink: TerminalSink;
  onStatus: (status: TtydStatus) => void;
  createSocket?: (url: string) => SocketLike;
  /** Delays before each automatic reconnect; once used up the connection stays closed. */
  retryDelaysMs?: readonly number[];
}

// ttyd's own client defaults: past `limit` bytes it counts xterm's unfinished
// writes and asks the server to pause above `highWater`, resume below `lowWater`.
// Without it a burst of agent output queues unbounded work in the parser.
const FLOW_LIMIT = 100_000;
const FLOW_HIGH_WATER = 10;
const FLOW_LOW_WATER = 4;

// About 2 minutes in all: a runner's tunnel redials with a backoff of up to 60 s, so after a
// relay restart the terminal is back only when the machine has dialed again.
const DEFAULT_RETRY_DELAYS_MS = [1_000, 2_000, 4_000, 8_000, 15_000, 15_000, 15_000, 15_000, 30_000, 30_000];

const OPEN = 1;
// ttyd closes with 1000 when the command exits (the tmux session ended), but a relay
// restart drains the stream the same way, so a 1000 close is retried once. Another 1000
// with no output in between is the end of the session.
const CLOSE_NORMAL = 1000;

export class TtydConnection {
  private readonly options: TtydConnectionOptions;
  private socket: SocketLike | null = null;
  private retries = 0;
  private normalCloses = 0;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private opened = false;
  private disposed = false;
  private written = 0;
  private pending = 0;

  constructor(options: TtydConnectionOptions) {
    this.options = options;
  }

  connect(): void {
    if (this.disposed) return;
    this.clearRetry();
    this.options.onStatus(this.opened ? 'reconnecting' : 'connecting');

    const create = this.options.createSocket ?? ((url: string) => new WebSocket(url, [TTYD_SUBPROTOCOL]));
    const socket = create(this.options.url());
    socket.binaryType = 'arraybuffer';
    this.socket = socket;
    this.written = 0;
    this.pending = 0;

    socket.addEventListener('open', () => {
      if (socket !== this.socket) return;
      const { sink } = this.options;
      socket.send(encodeHandshake(sink.cols, sink.rows));
      // tmux repaints the whole screen for a new client, so a reconnect starts clean.
      if (this.opened) sink.reset();
      this.opened = true;
      this.retries = 0;
      this.options.onStatus('open');
    });

    socket.addEventListener('message', (event) => {
      if (socket !== this.socket) return;
      const frame = decodeFrame((event as MessageEvent<ArrayBuffer>).data);
      if (frame.type === 'output') {
        this.normalCloses = 0;
        this.write(frame.data);
      }
    });

    socket.addEventListener('close', (event) => {
      if (socket !== this.socket) return;
      this.socket = null;
      const delays = this.options.retryDelaysMs ?? DEFAULT_RETRY_DELAYS_MS;
      let retryable = this.retries < delays.length;
      if ((event as CloseEvent).code === CLOSE_NORMAL) {
        this.normalCloses += 1;
        retryable = retryable && this.normalCloses <= 1;
      }
      if (this.disposed || !retryable) {
        this.options.onStatus('closed');
        return;
      }
      this.options.onStatus('reconnecting');
      this.retryTimer = setTimeout(() => this.connect(), delays[this.retries]);
      this.retries += 1;
    });
  }

  /** A manual reconnect after the connection gave up; restarts the retry budget. */
  reconnect(): void {
    this.retries = 0;
    this.normalCloses = 0;
    this.connect();
  }

  input(data: string | Uint8Array): void {
    this.send(encodeInput(data));
  }

  resize(cols: number, rows: number): void {
    this.send(encodeResize(cols, rows));
  }

  dispose(): void {
    this.disposed = true;
    this.clearRetry();
    const socket = this.socket;
    this.socket = null;
    socket?.close();
  }

  private write(data: Uint8Array): void {
    const { sink } = this.options;
    this.written += data.length;
    if (this.written <= FLOW_LIMIT) {
      sink.write(data);
      return;
    }
    this.written = 0;
    this.pending += 1;
    sink.write(data, () => {
      this.pending = Math.max(this.pending - 1, 0);
      if (this.pending < FLOW_LOW_WATER) this.send(RESUME_FRAME);
    });
    if (this.pending > FLOW_HIGH_WATER) this.send(PAUSE_FRAME);
  }

  private send(frame: Uint8Array<ArrayBuffer>): void {
    if (this.socket?.readyState === OPEN) this.socket.send(frame);
  }

  private clearRetry(): void {
    if (this.retryTimer !== null) clearTimeout(this.retryTimer);
    this.retryTimer = null;
  }
}
