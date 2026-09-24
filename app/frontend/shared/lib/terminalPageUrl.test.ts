import { describe, expect, it } from 'vitest';

import { stripContainerTicket, terminalPageUrl } from './terminalPageUrl';

describe('terminalPageUrl', () => {
  it('uses the page URL the server sends', () => {
    expect(
      terminalPageUrl({
        terminalUrl: 'https://t.example.com/t/abc/tty?aixle_ticket=x',
        websocketUrl: 'wss://other/ws',
      }),
    ).toBe('https://t.example.com/t/abc/tty?aixle_ticket=x');
  });

  it('derives it from the websocket URL of a pod that predates the field, keeping the ticket', () => {
    expect(terminalPageUrl({ websocketUrl: 'wss://ws.example.com/t/abc/tty/ws?aixle_ticket=a%2Bb' })).toBe(
      'https://ws.example.com/t/abc/tty?aixle_ticket=a%2Bb',
    );
    expect(terminalPageUrl({ websocketUrl: 'ws://localhost/t/abc/view/ws' })).toBe('http://localhost/t/abc/view');
  });

  it('has no page without either URL', () => {
    expect(terminalPageUrl({ terminalUrl: null, websocketUrl: null })).toBeNull();
  });
});

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
