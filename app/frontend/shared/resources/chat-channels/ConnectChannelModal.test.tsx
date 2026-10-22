import '@testing-library/jest-dom/vitest';
import type { ComponentProps } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { buildChatChannel, buildChatConnectCode } from 'test/factories/chatChannel';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { act, renderPage, screen, userEvent, within } from 'test/renderPage';

import { ConnectChannelModal } from './ConnectChannelModal';
import type { ChatConnectCode } from './types';

const CODES = '/api/v1/projects/7/chat_connect_codes';

type ModalProps = ComponentProps<typeof ConnectChannelModal>;

const render = (overrides: Partial<ModalProps> = {}) =>
  renderPage(
    <ConnectChannelModal
      projectId={7}
      provider="slack"
      opened
      onClose={vi.fn()}
      onConnected={vi.fn()}
      {...overrides}
    />,
  );

const inTenMinutes = () => new Date(Date.now() + 10 * 60_000).toISOString();

// The show endpoint never repeats the code or the line to post (undefined keys drop out of the JSON).
const polled = (issued: ChatConnectCode, overrides: Partial<ChatConnectCode> = {}): ChatConnectCode => ({
  ...issued,
  command: undefined,
  code: undefined,
  ...overrides,
});

const requestsTo = (spy: ReturnType<typeof answerFetch>, method: string, path: string) =>
  spy.mock.calls.filter(([url, init]) => (init?.method ?? 'GET') === method && String(url) === path);

const bodiesPosted = (spy: ReturnType<typeof answerFetch>) =>
  requestsTo(spy, 'POST', CODES).map(([, init]) => JSON.parse(init?.body as string));

const nextPoll = () => act(() => vi.advanceTimersByTimeAsync(3000));

const openDialog = (name = 'Connect a Slack channel') => screen.findByRole('dialog', { name });

const requestCode = async (dialog: HTMLElement, channel = 'deploys') => {
  await userEvent.type(within(dialog).getByRole('textbox', { name: 'Channel' }), channel);
  await userEvent.click(within(dialog).getByRole('button', { name: 'Get code' }));
  return within(dialog).findByRole('textbox', { name: 'Message to post' });
};

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('ConnectChannelModal', () => {
  it('asks which Slack channel the code is for before asking for one', async () => {
    const fetchSpy = answerFetch({});
    render();

    const dialog = await openDialog();
    const input = within(dialog).getByRole('textbox', { name: 'Channel' });
    expect(input).toHaveAttribute('placeholder', '#deploys');
    expect(input).toHaveAccessibleDescription("The channel's name, with or without #.");
    expect(within(dialog).getByRole('button', { name: 'Get code' })).toBeDisabled();

    await userEvent.type(input, '   ');
    expect(within(dialog).getByRole('button', { name: 'Get code' })).toBeDisabled();
    await act(() => vi.advanceTimersByTimeAsync(10_000));

    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('asks for a code for the channel as typed and says how to post it there', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    render();
    const dialog = await openDialog();

    await userEvent.type(within(dialog).getByRole('textbox', { name: 'Channel' }), 'deploys{Enter}');

    expect(await within(dialog).findByRole('textbox', { name: 'Message to post' })).toHaveValue(
      'connect aixle-7F3K9QXM',
    );
    expect(bodiesPosted(fetchSpy)).toEqual([{ provider: 'slack', channel: 'deploys' }]);
    expect(within(dialog).getByText('Invite the bot to #deploys first', { exact: false })).toBeInTheDocument();
    expect(within(dialog).getByText('/invite @aixle-flow')).toBeInTheDocument();
    expect(within(dialog).getByText(/In #deploys, type/)).toBeInTheDocument();
    expect(within(dialog).getByText('@aixle-flow')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Copy the message' })).toBeInTheDocument();
    expect(within(dialog).getByText(/A mention pasted as plain text does not reach the bot/)).toBeInTheDocument();
    expect(within(dialog).getByText('Posted in any other channel, the code connects nothing.')).toBeInTheDocument();
    expect(within(dialog).getByRole('status')).toHaveTextContent('expires in 10:00');

    await act(() => vi.advanceTimersByTimeAsync(60_000));

    expect(within(dialog).getByRole('status')).toHaveTextContent('expires in 9:00');
  });

  it('asks on behalf of a trigger for a Teams channel named with its team, and says how to add the app', async () => {
    const issued = buildChatConnectCode({
      provider: 'teams',
      trigger_id: 9,
      channel_name: 'Sales / General',
      bot_name: 'Aixle Flow',
      mention: 'Aixle Flow',
      invite: 'Add Aixle Flow to the team or group chat',
      expires_at: inTenMinutes(),
    });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    render({ provider: 'teams', triggerId: 9 });
    const dialog = await openDialog('Connect a Microsoft Teams channel');

    const input = within(dialog).getByRole('textbox', { name: 'Channel' });
    expect(input).toHaveAttribute('placeholder', 'Sales / General');
    expect(input).toHaveAccessibleDescription(
      "Team / Channel, or a group chat's name. A Teams channel needs its team: every team has a General.",
    );
    await requestCode(dialog, 'Sales / General');

    expect(within(dialog).getByText('Invite the bot to Sales / General first', { exact: false })).toBeInTheDocument();
    expect(within(dialog).getByText('Add Aixle Flow to the team or group chat.')).toBeInTheDocument();
    expect(within(dialog).getByText(/In Sales \/ General, type/)).toBeInTheDocument();
    expect(within(dialog).getByText('Aixle Flow')).toBeInTheDocument();
    expect(bodiesPosted(fetchSpy)).toEqual([{ provider: 'teams', channel: 'Sales / General', trigger_id: 9 }]);
  });

  it('shows why no code could be issued and keeps the channel typed', async () => {
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse({ errors: ['Name the channel to connect: its name, such as #deploys'] }, 422),
    });
    render();
    const dialog = await openDialog();

    await userEvent.type(within(dialog).getByRole('textbox', { name: 'Channel' }), '#');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Get code' }));

    expect(
      await within(dialog).findByText('Name the channel to connect: its name, such as #deploys'),
    ).toBeInTheDocument();
    expect(within(dialog).getByRole('textbox', { name: 'Channel' })).toHaveValue('#');
    expect(within(dialog).getByRole('button', { name: 'Get code' })).toBeEnabled();
    expect(within(dialog).queryByRole('textbox', { name: 'Message to post' })).not.toBeInTheDocument();
    expect(bodiesPosted(fetchSpy)).toEqual([{ provider: 'slack', channel: '#' }]);
  });

  it('reports the channel once the code has been posted there, and stops asking', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const deploys = buildChatChannel({ id: 12 });
    let answer = polled(issued);
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: () => answer,
    });
    const onConnected = vi.fn();
    render({ onConnected });
    const dialog = await openDialog();
    await requestCode(dialog);

    await nextPoll();
    expect(onConnected).not.toHaveBeenCalled();
    answer = polled(issued, { state: 'redeemed', channel: deploys });
    await nextPoll();

    expect(await within(dialog).findByText('Connected to #deploys')).toBeInTheDocument();
    expect(onConnected).toHaveBeenCalledExactlyOnceWith(deploys);
    const polls = requestsTo(fetchSpy, 'GET', `${CODES}/31`).length;
    await nextPoll();
    expect(requestsTo(fetchSpy, 'GET', `${CODES}/31`)).toHaveLength(polls);
    expect(onConnected).toHaveBeenCalledTimes(1);
  });

  it('says why a post in another channel was refused, and keeps waiting for the same code', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    let answer = polled(issued, { failure_reason: 'Posted in #random, but the code is for #deploys' });
    answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: () => answer,
    });
    const onConnected = vi.fn();
    render({ onConnected });
    const dialog = await openDialog();
    await requestCode(dialog);

    await nextPoll();

    expect(
      await within(dialog).findByText('The last attempt was refused: Posted in #random, but the code is for #deploys'),
    ).toBeInTheDocument();
    expect(within(dialog).getByRole('status')).toHaveTextContent('Waiting for the message');
    expect(within(dialog).getByRole('textbox', { name: 'Message to post' })).toHaveValue('connect aixle-7F3K9QXM');

    answer = polled(issued, { state: 'redeemed', channel: buildChatChannel() });
    await nextPoll();

    expect(await within(dialog).findByText('Connected to #deploys')).toBeInTheDocument();
    expect(onConnected).toHaveBeenCalledOnce();
  });

  it('goes back to the channel typed for a new code once this one expired', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const renewed = buildChatConnectCode({
      id: 32,
      channel_name: '#releases',
      command: 'connect aixle-QQ2RT8WM',
      expires_at: inTenMinutes(),
    });
    let created = issued;
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: () => jsonResponse(created, 201),
      [`GET ${CODES}/31`]: polled(issued, { state: 'expired' }),
      [`GET ${CODES}/32`]: polled(renewed),
    });
    render();
    const dialog = await openDialog();
    await requestCode(dialog);

    await nextPoll();
    expect(await within(dialog).findByText('This code has expired.')).toBeInTheDocument();
    await userEvent.click(within(dialog).getByRole('button', { name: 'Get a new code' }));

    const input = within(dialog).getByRole('textbox', { name: 'Channel' });
    expect(input).toHaveValue('deploys');
    created = renewed;
    await userEvent.clear(input);
    await userEvent.type(input, 'releases');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Get code' }));

    expect(await within(dialog).findByRole('textbox', { name: 'Message to post' })).toHaveValue(
      'connect aixle-QQ2RT8WM',
    );
    expect(within(dialog).getByText('Invite the bot to #releases first', { exact: false })).toBeInTheDocument();
    expect(within(dialog).queryByText('This code has expired.')).not.toBeInTheDocument();
    expect(bodiesPosted(fetchSpy)).toEqual([
      { provider: 'slack', channel: 'deploys' },
      { provider: 'slack', channel: 'releases' },
    ]);
  });

  it('changes the channel while a code is pending, and stops asking about that code', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    render();
    const dialog = await openDialog();
    await requestCode(dialog, '#deplys');

    await userEvent.click(within(dialog).getByRole('button', { name: 'Change channel' }));

    expect(within(dialog).getByRole('textbox', { name: 'Channel' })).toHaveValue('#deplys');
    expect(within(dialog).queryByRole('textbox', { name: 'Message to post' })).not.toBeInTheDocument();
    const polls = requestsTo(fetchSpy, 'GET', `${CODES}/31`).length;
    await act(() => vi.advanceTimersByTimeAsync(30_000));
    expect(requestsTo(fetchSpy, 'GET', `${CODES}/31`)).toHaveLength(polls);
  });

  it('stops asking once it is closed, and opens again on an empty channel', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    const { rerender } = render();
    await requestCode(await openDialog());

    rerender(
      <ConnectChannelModal projectId={7} provider="slack" opened={false} onClose={vi.fn()} onConnected={vi.fn()} />,
    );
    await act(() => vi.advanceTimersByTimeAsync(30_000));

    expect(requestsTo(fetchSpy, 'GET', `${CODES}/31`)).toHaveLength(0);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();

    rerender(<ConnectChannelModal projectId={7} provider="slack" opened onClose={vi.fn()} onConnected={vi.fn()} />);

    expect(within(await openDialog()).getByRole('textbox', { name: 'Channel' })).toHaveValue('');
  });
});
