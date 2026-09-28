import { describe, expect, it } from 'vitest';

import { stripContainerTicket } from './containerTicket';

describe('stripContainerTicket', () => {
  it('drops the pass and keeps the rest of the URL', () => {
    expect(
      stripContainerTicket('https://t.example.com/t/abc/fs/preload?to=%2Fide%3Ffolder%3D%2Fw&aixle_ticket=a%2Bb'),
    ).toBe('https://t.example.com/t/abc/fs/preload?to=%2Fide%3Ffolder%3D%2Fw');
    expect(stripContainerTicket('https://t.example.com/t/abc/tty?aixle_ticket=x')).toBe(
      'https://t.example.com/t/abc/tty',
    );
  });

  it('leaves a URL without a pass, or one it cannot parse, as it is', () => {
    expect(stripContainerTicket('https://t.example.com/t/abc/tty')).toBe('https://t.example.com/t/abc/tty');
    expect(stripContainerTicket('/relative/path')).toBe('/relative/path');
  });
});
