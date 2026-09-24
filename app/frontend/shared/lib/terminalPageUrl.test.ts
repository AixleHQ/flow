import { describe, expect, it } from 'vitest';

import { terminalPageUrl } from './terminalPageUrl';

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
