import { describe, expect, it } from 'vitest';

import { decodeFrame, encodeHandshake, encodeInput, encodeResize } from './ttydProtocol';

const text = (bytes: Uint8Array) => new TextDecoder().decode(bytes);
const frame = (command: string, body: string) => new TextEncoder().encode(command + body).buffer;

describe('ttydProtocol', () => {
  it('opens with an untagged JSON handshake carrying the terminal size', () => {
    expect(JSON.parse(text(encodeHandshake(120, 40)))).toEqual({ AuthToken: '', columns: 120, rows: 40 });
  });

  it('tags keystrokes with the input command, text and raw bytes alike', () => {
    expect(text(encodeInput('ls\r'))).toBe('0ls\r');
    expect(text(encodeInput('é'))).toBe('0é');
    expect(Array.from(encodeInput(Uint8Array.of(0x1b, 0xff)))).toEqual([0x30, 0x1b, 0xff]);
  });

  it('tags a resize with its command and a JSON size', () => {
    const encoded = text(encodeResize(80, 24));
    expect(encoded[0]).toBe('1');
    expect(JSON.parse(encoded.slice(1))).toEqual({ columns: 80, rows: 24 });
  });

  it('decodes output, window titles and preferences from the server', () => {
    const output = decodeFrame(frame('0', '\x1b[31mred'));
    expect(output.type).toBe('output');
    expect(output.type === 'output' && text(output.data)).toBe('\x1b[31mred');

    expect(decodeFrame(frame('1', 'bash'))).toEqual({ type: 'title', title: 'bash' });
    expect(decodeFrame(frame('2', '{"fontSize":14}'))).toEqual({ type: 'preferences' });
    expect(decodeFrame(frame('9', ''))).toEqual({ type: 'unknown' });
    expect(decodeFrame(new ArrayBuffer(0))).toEqual({ type: 'unknown' });
  });
});
