import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, waitFor } from 'test/renderPage';

import { SessionTerminalReplay } from './SessionTerminalReplay';

// xterm.js is a vendor module (jsdom has no canvas/WebGL), so per docs/testing.md R8
// the third-party seam may be mocked. We assert the component feeds fetched bytes into
// the stubbed terminal rather than rendering pixels.
const write = vi.fn();
const dispose = vi.fn();
const loadAddon = vi.fn();
const open = vi.fn();
const fit = vi.fn();

vi.mock('@xterm/xterm', () => ({
  Terminal: vi.fn(function Terminal() {
    return { loadAddon, open, write, dispose };
  }),
}));
vi.mock('@xterm/addon-fit', () => ({
  FitAddon: vi.fn(function FitAddon() {
    return { fit };
  }),
}));
vi.mock('@xterm/xterm/css/xterm.css', () => ({}));

const LOG_URL = '/api/v1/terminal_sessions/7/terminal_log';

describe('SessionTerminalReplay', () => {
  beforeEach(() => {
    write.mockClear();
    open.mockClear();
    loadAddon.mockClear();
    fit.mockClear();
  });

  it('fetches the log and writes the raw ANSI bytes into the terminal', async () => {
    const body = '[31mred[0m output';
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(body, { status: 200 }));

    renderPage(<SessionTerminalReplay logUrl={LOG_URL} />);

    await waitFor(() => expect(write).toHaveBeenCalledWith(body));
    expect(fetchSpy).toHaveBeenCalledWith(LOG_URL, expect.anything());
    fetchSpy.mockRestore();
  });

  it('shows an empty-state message when the log is missing (404)', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 404 }));

    renderPage(<SessionTerminalReplay logUrl={LOG_URL} />);

    expect(await screen.findByText(/no terminal output was captured/i)).toBeInTheDocument();
    expect(write).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it('flags a server-truncated log and drops the partial first line', async () => {
    // Server tail may start mid-line; the component drops up to the first newline.
    const body = 'rtial-first-line\x1b[0m\nclean line one\nclean line two';
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(body, { status: 200, headers: { 'X-Log-Truncated': 'true' } }));

    renderPage(<SessionTerminalReplay logUrl={LOG_URL} />);

    expect(await screen.findByText(/log truncated/i)).toBeInTheDocument();
    await waitFor(() => expect(write).toHaveBeenCalled());
    expect(write.mock.calls[0][0] as string).toBe('clean line one\nclean line two');
    fetchSpy.mockRestore();
  });
});
