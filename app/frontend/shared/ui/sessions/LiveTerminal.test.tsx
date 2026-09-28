import { beforeEach, describe, expect, it, vi } from 'vitest';

import { FakeWebSocket, installFakeWebSocket } from 'test/fakeWebSocket';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { act, fireEvent, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { ColorSchemeToggle } from 'shared/ui/ColorSchemeToggle';

import { LiveTerminal } from './LiveTerminal';

const URL_WITH_PASS = 'wss://sandbox.test/t/abc123/tty/ws?aixle_ticket=first';

const UPLOAD_URL = 'http://sandbox.test/t/abc123/upload?aixle_ticket=first';

const fromTmux = (socket: FakeWebSocket, text: string) =>
  act(() => socket.receive(new TextEncoder().encode(`0${text}`)));

// What reached ttyd as input (command byte '0'), in order.
const typed = (socket: FakeWebSocket) => socket.sent.filter((f) => f.startsWith('0')).map((f) => f.slice(1));

const png = () => new File(['png-bytes'], 'shot.png', { type: 'image/png' });

async function connected() {
  await waitFor(() => expect(FakeWebSocket.latest()).toBeDefined());
  const socket = FakeWebSocket.latest()!;
  act(() => socket.open());
  return socket;
}

describe('LiveTerminal', () => {
  beforeEach(() => {
    installFakeWebSocket();
  });

  it("connects to the container's ttyd and sends what the owner types", async () => {
    renderPage(<LiveTerminal url={URL_WITH_PASS} />);
    expect(screen.getByText('Connecting to terminal…')).toBeInTheDocument();

    const socket = await connected();

    expect(socket.url).toBe(URL_WITH_PASS);
    expect(socket.protocols).toEqual(['tty']);
    expect(JSON.parse(socket.sent[0])).toMatchObject({ AuthToken: '' });
    expect(screen.queryByText('Connecting to terminal…')).not.toBeInTheDocument();

    await userEvent.type(screen.getByRole('textbox', { name: 'Terminal input' }), 'ls');
    expect(socket.sent).toEqual(expect.arrayContaining(['0l', '0s']));
  });

  it("sends nothing typed into someone else's session", async () => {
    renderPage(<LiveTerminal url={URL_WITH_PASS} readOnly />);
    const socket = await connected();

    expect(screen.getByRole('group', { name: "Read-only view of another user's session" })).toBeInTheDocument();
    await userEvent.type(screen.getByRole('textbox', { name: 'Terminal input' }), 'rm');
    expect(socket.sent.filter((frame) => frame.startsWith('0'))).toEqual([]);
  });

  it('keeps its connection when only the pass in the URL changes', async () => {
    const { rerender } = renderPage(<LiveTerminal url={URL_WITH_PASS} />);
    await connected();

    rerender(<LiveTerminal url="wss://sandbox.test/t/abc123/tty/ws?aixle_ticket=second" />);

    expect(FakeWebSocket.instances).toHaveLength(1);
  });

  it('offers a reconnect once the session closes the terminal', async () => {
    renderPage(<LiveTerminal url={URL_WITH_PASS} />);
    const socket = await connected();

    act(() => socket.drop(1000));
    await userEvent.click(await screen.findByRole('button', { name: 'Reconnect' }));

    expect(FakeWebSocket.instances).toHaveLength(2);
  });

  // jsdom reports no platform, which is what a Windows or Linux browser gets.
  // xterm maps Ctrl+letter from keyCode, which user-event leaves at 0.
  describe('clipboard keys off the Mac', () => {
    const CTRL_C = { key: 'c', code: 'KeyC', keyCode: 67, ctrlKey: true };
    const CTRL_V = { key: 'v', code: 'KeyV', keyCode: 86, ctrlKey: true };

    it('still interrupts with Ctrl+C when nothing is selected', async () => {
      renderPage(<LiveTerminal url={URL_WITH_PASS} />);
      const socket = await connected();

      fireEvent.keyDown(screen.getByRole('textbox', { name: 'Terminal input' }), CTRL_C);

      await waitFor(() => expect(typed(socket)).toContain('\x03'));
    });

    it("leaves Ctrl+V to the browser's paste instead of sending ^V", async () => {
      renderPage(<LiveTerminal url={URL_WITH_PASS} />);
      const socket = await connected();

      const input = screen.getByRole('textbox', { name: 'Terminal input' });
      const keydown = fireEvent.keyDown(input, CTRL_V);
      fireEvent.keyDown(input, CTRL_C);
      await waitFor(() => expect(typed(socket)).toContain('\x03'));

      expect(keydown).toBe(true); // not prevented: the browser goes on to paste
      expect(typed(socket)).not.toContain('\x16');
    });
  });

  describe('theme', () => {
    // Mantine keeps the chosen scheme in localStorage; each test starts dark.
    beforeEach(() => localStorage.clear());

    it('tells tmux the new theme once tmux asked to hear about it', async () => {
      renderPage(
        <>
          <ColorSchemeToggle />
          <LiveTerminal url={URL_WITH_PASS} />
        </>,
      );
      const socket = await connected();
      await fromTmux(socket, '\x1b[?2031h');

      await userEvent.click(await screen.findByRole('button', { name: 'Switch to light theme' }));

      await waitFor(() => expect(typed(socket)).toContain('\x1b[?997;2n'));
    });

    it('stays quiet about the theme to a tmux that never asked', async () => {
      renderPage(
        <>
          <ColorSchemeToggle />
          <LiveTerminal url={URL_WITH_PASS} />
        </>,
      );
      const socket = await connected();

      await userEvent.click(await screen.findByRole('button', { name: 'Switch to light theme' }));

      expect(typed(socket).some((input) => input.includes('997'))).toBe(false);
    });

    it('answers when tmux asks for the current theme', async () => {
      renderPage(<LiveTerminal url={URL_WITH_PASS} />);
      const socket = await connected();

      await fromTmux(socket, '\x1b[?996n');

      await waitFor(() => expect(typed(socket)).toContain('\x1b[?997;1n'));
    });

    it('makes the CLI repaint by resizing once the theme has settled', async () => {
      vi.useFakeTimers({ shouldAdvanceTime: true });
      try {
        renderPage(
          <>
            <ColorSchemeToggle />
            <LiveTerminal url={URL_WITH_PASS} />
          </>,
        );
        const socket = await connected();
        await fromTmux(socket, '\x1b[?2031h');
        await userEvent.click(await screen.findByRole('button', { name: 'Switch to light theme' }));
        await waitFor(() => expect(typed(socket)).toContain('\x1b[?997;2n'));

        const resizes = () => socket.sent.filter((f) => f.startsWith('1')).map((f) => JSON.parse(f.slice(1)));
        const before = resizes().length;

        act(() => vi.advanceTimersByTime(2600));

        const [shrunk, restored] = resizes().slice(before);
        expect(shrunk.columns).toBe(restored.columns - 1);
        expect(restored.rows).toBe(shrunk.rows);
      } finally {
        vi.useRealTimers();
      }
    });
  });

  describe('pasting an image', () => {
    it('stores it in the container and pastes its path to the CLI', async () => {
      answerFetch({ [`POST ${UPLOAD_URL.split('?')[0]}`]: jsonResponse({ path: '/tmp/aixle-uploads/a.png' }, 201) });
      renderPage(<LiveTerminal url={URL_WITH_PASS} uploadUrl={UPLOAD_URL} />);
      const socket = await connected();

      fireEvent.paste(screen.getByRole('textbox', { name: 'Terminal input' }), {
        clipboardData: { files: [png()], types: ['Files'], getData: () => '' },
      });

      await waitFor(() => expect(typed(socket)).toContain('/tmp/aixle-uploads/a.png'));
    });

    it('says why when the container refuses it', async () => {
      answerFetch({
        [`POST ${UPLOAD_URL.split('?')[0]}`]: jsonResponse({ error: 'Images are limited to 10.0 MB' }, 413),
      });
      renderPage(<LiveTerminal url={URL_WITH_PASS} uploadUrl={UPLOAD_URL} />);
      await connected();

      fireEvent.paste(screen.getByRole('textbox', { name: 'Terminal input' }), {
        clipboardData: { files: [png()], types: ['Files'], getData: () => '' },
      });

      expect(await screen.findByRole('alert')).toHaveTextContent('Images are limited to 10.0 MB');
    });

    it('accepts an image dropped onto the terminal', async () => {
      answerFetch({ [`POST ${UPLOAD_URL.split('?')[0]}`]: jsonResponse({ path: '/tmp/aixle-uploads/b.png' }, 201) });
      renderPage(<LiveTerminal url={URL_WITH_PASS} uploadUrl={UPLOAD_URL} />);
      const socket = await connected();

      fireEvent.drop(screen.getByRole('group', { name: 'Terminal' }), {
        dataTransfer: { files: [png()], types: ['Files'] },
      });

      await waitFor(() => expect(typed(socket)).toContain('/tmp/aixle-uploads/b.png'));
    });

    it("uploads nothing into someone else's session", async () => {
      renderPage(<LiveTerminal url={URL_WITH_PASS} uploadUrl={UPLOAD_URL} readOnly />);
      const socket = await connected();

      fireEvent.paste(screen.getByRole('textbox', { name: 'Terminal input' }), {
        clipboardData: { files: [png()], types: ['Files'], getData: () => '' },
      });

      expect(typed(socket)).toEqual([]);
    });
  });
});
