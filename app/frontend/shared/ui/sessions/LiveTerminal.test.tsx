import { beforeEach, describe, expect, it } from 'vitest';

import { FakeWebSocket, installFakeWebSocket } from 'test/fakeWebSocket';
import { act, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { LiveTerminal } from './LiveTerminal';

const URL_WITH_PASS = 'wss://sandbox.test/t/abc123/tty/ws?aixle_ticket=first';

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
});
