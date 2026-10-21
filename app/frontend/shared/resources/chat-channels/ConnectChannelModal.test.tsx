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

const nextPoll = () => act(() => vi.advanceTimersByTimeAsync(3000));

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('ConnectChannelModal', () => {
  it('asks for a code on opening and says how to post it in the channel', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    render();

    const dialog = await screen.findByRole('dialog', { name: 'Connect a Slack channel' });
    expect(await within(dialog).findByRole('textbox', { name: 'Message to post' })).toHaveValue(
      'connect aixle-7F3K9QXM',
    );
    expect(JSON.parse(requestsTo(fetchSpy, 'POST', CODES)[0][1]?.body as string)).toEqual({ provider: 'slack' });
    expect(within(dialog).getByText('Invite the bot first', { exact: false })).toBeInTheDocument();
    expect(within(dialog).getByText('/invite @aixle-flow')).toBeInTheDocument();
    expect(within(dialog).getByText('@aixle-flow')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Copy the message' })).toBeInTheDocument();
    expect(within(dialog).getByText(/Teams ignores a typed @name/)).toBeInTheDocument();
    expect(within(dialog).getByRole('status')).toHaveTextContent('expires in 10:00');

    await act(() => vi.advanceTimersByTimeAsync(60_000));

    expect(within(dialog).getByRole('status')).toHaveTextContent('expires in 9:00');
  });

  it('asks on behalf of a trigger, and says how to add the Teams app', async () => {
    const issued = buildChatConnectCode({
      provider: 'teams',
      trigger_id: 9,
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

    const dialog = await screen.findByRole('dialog', { name: 'Connect a Microsoft Teams channel' });
    expect(await within(dialog).findByText('Add Aixle Flow to the team or group chat.')).toBeInTheDocument();
    expect(within(dialog).getByText('Aixle Flow')).toBeInTheDocument();
    expect(JSON.parse(requestsTo(fetchSpy, 'POST', CODES)[0][1]?.body as string)).toEqual({
      provider: 'teams',
      trigger_id: 9,
    });
  });

  it('reports the channel once the code has been posted there, and stops asking', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const releases = buildChatChannel({ id: 12, name: 'releases', label: '#releases' });
    let answer = polled(issued);
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: () => answer,
    });
    const onConnected = vi.fn();
    render({ onConnected });
    const dialog = await screen.findByRole('dialog', { name: 'Connect a Slack channel' });
    await within(dialog).findByRole('textbox', { name: 'Message to post' });

    await nextPoll();
    expect(onConnected).not.toHaveBeenCalled();
    answer = polled(issued, { state: 'redeemed', channel: releases });
    await nextPoll();

    expect(await within(dialog).findByText('Connected to #releases')).toBeInTheDocument();
    expect(onConnected).toHaveBeenCalledExactlyOnceWith(releases);
    const polls = requestsTo(fetchSpy, 'GET', `${CODES}/31`).length;
    await nextPoll();
    expect(requestsTo(fetchSpy, 'GET', `${CODES}/31`)).toHaveLength(polls);
    expect(onConnected).toHaveBeenCalledTimes(1);
  });

  it('says why an attempt was refused, and offers a new code once this one expired', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const renewed = buildChatConnectCode({ id: 32, command: 'connect aixle-QQ2RT8WM', expires_at: inTenMinutes() });
    let created = issued;
    answerFetch({
      [`POST ${CODES}`]: () => jsonResponse(created, 201),
      [`GET ${CODES}/31`]: polled(issued, {
        state: 'expired',
        failure_reason: 'Posted in a direct chat, not in a channel',
      }),
      [`GET ${CODES}/32`]: polled(renewed),
    });
    render();
    const dialog = await screen.findByRole('dialog', { name: 'Connect a Slack channel' });
    await within(dialog).findByRole('textbox', { name: 'Message to post' });

    await nextPoll();

    expect(await within(dialog).findByText('This code has expired.')).toBeInTheDocument();
    expect(
      within(dialog).getByText('The last attempt was refused: Posted in a direct chat, not in a channel'),
    ).toBeInTheDocument();
    created = renewed;
    await userEvent.click(within(dialog).getByRole('button', { name: 'Get a new code' }));

    expect(await within(dialog).findByRole('textbox', { name: 'Message to post' })).toHaveValue(
      'connect aixle-QQ2RT8WM',
    );
    expect(within(dialog).queryByText('This code has expired.')).not.toBeInTheDocument();
  });

  it('shows why no code could be issued', async () => {
    answerFetch({
      [`POST ${CODES}`]: jsonResponse({ errors: ['Connect Slack on the Integrations page first'] }, 422),
    });
    render();

    const dialog = await screen.findByRole('dialog', { name: 'Connect a Slack channel' });
    expect(await within(dialog).findByText('Connect Slack on the Integrations page first')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Try again' })).toBeInTheDocument();
    expect(within(dialog).queryByRole('textbox', { name: 'Message to post' })).not.toBeInTheDocument();
  });

  it('stops asking once it is closed', async () => {
    const issued = buildChatConnectCode({ expires_at: inTenMinutes() });
    const fetchSpy = answerFetch({
      [`POST ${CODES}`]: jsonResponse(issued, 201),
      [`GET ${CODES}/31`]: polled(issued),
    });
    const { rerender } = render();
    await screen.findByRole('textbox', { name: 'Message to post' });

    rerender(
      <ConnectChannelModal projectId={7} provider="slack" opened={false} onClose={vi.fn()} onConnected={vi.fn()} />,
    );
    await act(() => vi.advanceTimersByTimeAsync(30_000));

    expect(requestsTo(fetchSpy, 'GET', `${CODES}/31`)).toHaveLength(0);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});
