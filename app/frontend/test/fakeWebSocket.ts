import { vi } from 'vitest';

type Listener = (event: unknown) => void;

/**
 * A browser WebSocket that never touches the network; jsdom's real one dials out.
 * Install it with `installFakeWebSocket()` — setup.ts unstubs globals after each test.
 */
export class FakeWebSocket {
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSING = 2;
  static readonly CLOSED = 3;
  static instances: FakeWebSocket[] = [];

  binaryType: BinaryType = 'blob';
  readyState = FakeWebSocket.CONNECTING;
  readonly sent: string[] = [];
  private readonly listeners: Record<string, Listener[]> = {};

  constructor(
    readonly url: string,
    readonly protocols?: string | string[],
  ) {
    FakeWebSocket.instances.push(this);
  }

  static latest(): FakeWebSocket | undefined {
    return FakeWebSocket.instances[FakeWebSocket.instances.length - 1];
  }

  addEventListener(type: string, listener: Listener) {
    (this.listeners[type] ??= []).push(listener);
  }

  removeEventListener(type: string, listener: Listener) {
    this.listeners[type] = (this.listeners[type] ?? []).filter((l) => l !== listener);
  }

  send(data: Uint8Array | string) {
    this.sent.push(typeof data === 'string' ? data : new TextDecoder().decode(data));
  }

  close() {
    this.readyState = FakeWebSocket.CLOSED;
  }

  /** Server side: accept the connection. */
  open() {
    this.readyState = FakeWebSocket.OPEN;
    this.emit('open', {});
  }

  /** Server side: send a binary frame. */
  receive(bytes: Uint8Array) {
    this.emit('message', { data: bytes.slice().buffer });
  }

  /** Server side: close the connection with `code`. */
  drop(code: number) {
    this.readyState = FakeWebSocket.CLOSED;
    this.emit('close', { code });
  }

  private emit(type: string, event: unknown) {
    this.listeners[type]?.forEach((listener) => listener(event));
  }
}

export function installFakeWebSocket() {
  FakeWebSocket.instances = [];
  vi.stubGlobal('WebSocket', FakeWebSocket);
}
