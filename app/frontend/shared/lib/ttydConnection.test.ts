import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { FakeWebSocket } from 'test/fakeWebSocket';

import { TtydConnection, type TerminalSink, type TtydStatus } from './ttydConnection';

class FakeSink implements TerminalSink {
  cols = 100;
  rows = 30;
  output = '';
  resets = 0;
  unfinished: (() => void)[] = [];

  write(data: Uint8Array, done?: () => void) {
    this.output += new TextDecoder().decode(data);
    if (done) this.unfinished.push(done);
  }

  reset() {
    this.resets += 1;
    this.output = '';
  }
}

const bytes = (frame: string) => new TextEncoder().encode(frame);

describe('TtydConnection', () => {
  let sockets: FakeWebSocket[];
  let statuses: TtydStatus[];
  let sink: FakeSink;
  let url: string;

  const start = (retryDelaysMs = [10, 20]) => {
    const connection = new TtydConnection({
      url: () => url,
      sink,
      onStatus: (status) => statuses.push(status),
      createSocket: (socketUrl) => {
        const socket = new FakeWebSocket(socketUrl);
        sockets.push(socket);
        return socket as unknown as WebSocket;
      },
      retryDelaysMs,
    });
    connection.connect();
    return connection;
  };
  const latest = () => sockets[sockets.length - 1];

  beforeEach(() => {
    vi.useFakeTimers();
    sockets = [];
    statuses = [];
    sink = new FakeSink();
    url = 'wss://sandbox.test/t/abc/tty/ws?aixle_ticket=first';
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('handshakes at the terminal size, then streams output in and keystrokes out', () => {
    const connection = start();
    expect(statuses).toEqual(['connecting']);
    expect(latest().binaryType).toBe('arraybuffer');

    latest().open();
    latest().receive(bytes('0hello\r\n'));
    connection.input('ls\r');
    connection.resize(120, 40);

    expect(statuses).toEqual(['connecting', 'open']);
    expect(JSON.parse(latest().sent[0])).toEqual({ AuthToken: '', columns: 100, rows: 30 });
    expect(latest().sent.slice(1)).toEqual(['0ls\r', '1{"columns":120,"rows":40}']);
    expect(sink.output).toBe('hello\r\n');
  });

  it('drops keystrokes typed before the socket opens', () => {
    const connection = start();
    connection.input('x');

    expect(latest().sent).toEqual([]);
  });

  it('reconnects after a dropped connection with the current pass and a clean screen', () => {
    start();
    latest().open();
    latest().receive(bytes('0old screen'));

    url = 'wss://sandbox.test/t/abc/tty/ws?aixle_ticket=second';
    latest().drop(1006);
    expect(statuses.at(-1)).toBe('reconnecting');

    vi.advanceTimersByTime(10);
    expect(sockets).toHaveLength(2);
    expect(latest().url).toBe(url);

    latest().open();
    expect(sink.resets).toBe(1);
    expect(statuses.at(-1)).toBe('open');
  });

  it('stays closed when the session ends, until reconnected by hand', () => {
    const connection = start();
    latest().open();
    latest().drop(1000);

    vi.advanceTimersByTime(1_000);
    expect(sockets).toHaveLength(1);
    expect(statuses.at(-1)).toBe('closed');

    connection.reconnect();
    expect(sockets).toHaveLength(2);
    expect(statuses.at(-1)).toBe('reconnecting');
  });

  it('gives up once the retry delays are used up', () => {
    start([10]);
    latest().drop(1006);
    vi.advanceTimersByTime(10);
    latest().drop(1006);
    vi.advanceTimersByTime(1_000);

    expect(sockets).toHaveLength(2);
    expect(statuses.at(-1)).toBe('closed');
  });

  it('asks the server to pause while the terminal falls behind, and to resume once it catches up', () => {
    start();
    latest().open();
    const chunk = bytes(`0${'x'.repeat(100_001)}`);
    for (let i = 0; i < 11; i += 1) latest().receive(chunk);
    expect(latest().sent.filter((frame) => frame === '2')).toHaveLength(1);

    sink.unfinished.splice(0, 8).forEach((done) => done());
    expect(latest().sent.filter((frame) => frame === '3').length).toBeGreaterThan(0);
  });

  it('closes the socket and cancels a pending retry on dispose', () => {
    const connection = start();
    latest().drop(1006);
    connection.dispose();
    vi.advanceTimersByTime(1_000);

    expect(sockets).toHaveLength(1);

    const second = start();
    second.dispose();
    expect(latest().readyState).toBe(FakeWebSocket.CLOSED);
  });
});
