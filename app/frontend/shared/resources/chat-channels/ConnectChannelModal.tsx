import {
  ActionIcon,
  Alert,
  Button,
  Code,
  CopyButton,
  Group,
  Loader,
  Modal,
  Stack,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { IconAlertCircle, IconCheck, IconCopy } from '@tabler/icons-react';
import { type ReactNode, useCallback, useEffect, useRef, useState } from 'react';

import { ApiError, apiRequest } from 'shared/lib/apiFetch';
import { CHAT_PROVIDER_LABELS } from 'shared/resources/triggers/describeTrigger';
import { apiV1ProjectChatConnectCodePath, apiV1ProjectChatConnectCodesPath } from 'shared/routes';

import { channelName } from './channelName';
import type { ChatChannel, ChatConnectCode } from './types';

const POLL_INTERVAL_MS = 3000;

interface ConnectChannelModalProps {
  projectId: number;
  provider: string;
  // The chat trigger the channel is for: redeeming the code points that trigger at it.
  triggerId?: number;
  opened: boolean;
  onClose: () => void;
  onConnected: (channel: ChatChannel) => void;
}

function formatRemaining(ms: number): string {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

function Step({ number, title, children }: { number: number; title: ReactNode; children?: ReactNode }) {
  return (
    <Stack gap={6}>
      <Text size="sm" fw={600}>
        {number}. {title}
      </Text>
      {children}
    </Stack>
  );
}

/**
 * Connects a Slack or Teams channel to the company with a one-time code: the
 * person posts it in the channel, the bot connects the channel it came from and
 * says so there. A channel id is never typed.
 */
export const ConnectChannelModal = ({
  projectId,
  provider,
  triggerId,
  opened,
  onClose,
  onConnected,
}: ConnectChannelModalProps) => {
  const [code, setCode] = useState<ChatConnectCode | null>(null);
  const [issuing, setIssuing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());
  // Each request for a code supersedes the one before it, and closing drops both.
  const attempt = useRef(0);
  // StrictMode runs effects twice, and every code issued counts against the company's cap of open codes.
  const issuedThisOpening = useRef(false);
  const reported = useRef<number | null>(null);
  const label = CHAT_PROVIDER_LABELS[provider] ?? provider;

  const issue = useCallback(async () => {
    const current = ++attempt.current;
    setCode(null);
    setError(null);
    setIssuing(true);
    try {
      const created = await apiRequest<ChatConnectCode>(apiV1ProjectChatConnectCodesPath(projectId), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ provider, ...(triggerId ? { trigger_id: triggerId } : {}) }),
      });
      if (current === attempt.current) setCode(created);
    } catch (e) {
      if (current === attempt.current) setError(e instanceof ApiError ? e.message : 'The code could not be created');
    } finally {
      if (current === attempt.current) setIssuing(false);
    }
  }, [projectId, provider, triggerId]);

  useEffect(() => {
    if (opened) {
      if (!issuedThisOpening.current) {
        issuedThisOpening.current = true;
        issue();
      }
      return;
    }
    issuedThisOpening.current = false;
    attempt.current += 1;
    setCode(null);
    setError(null);
    setIssuing(false);
  }, [opened, issue]);

  const pending = code?.state === 'pending';
  const codeId = code?.id;

  useEffect(() => {
    if (!opened || !pending || codeId === undefined) return;
    let cancelled = false;
    const poll = async () => {
      try {
        const latest = await apiRequest<ChatConnectCode>(apiV1ProjectChatConnectCodePath(projectId, codeId));
        if (!cancelled) setCode((prev) => (prev?.id === latest.id ? { ...prev, ...latest } : prev));
      } catch {
        // The next poll asks again.
      }
    };
    const timer = window.setInterval(poll, POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [opened, pending, codeId, projectId]);

  useEffect(() => {
    if (!opened || !pending) return;
    setNow(Date.now());
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [opened, pending]);

  useEffect(() => {
    if (code?.state !== 'redeemed' || !code.channel || reported.current === code.id) return;
    reported.current = code.id;
    onConnected(code.channel);
  }, [code, onConnected]);

  return (
    <Modal opened={opened} onClose={onClose} title={`Connect a ${label} channel`} centered size="md">
      {issuing ? (
        <Group justify="center" py="md">
          <Loader size="sm" aria-label="Creating a code" />
        </Group>
      ) : error ? (
        <Stack gap="md">
          <Alert color="red" variant="light" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Close
            </Button>
            <Button onClick={issue}>Try again</Button>
          </Group>
        </Stack>
      ) : code?.state === 'redeemed' ? (
        <Stack gap="md">
          <Alert color="green" variant="light" icon={<IconCheck size={16} />}>
            Connected to {code.channel ? channelName(code.channel) : 'the channel'}
          </Alert>
          <Text size="sm">
            The bot confirmed it in the channel. Every project of your company can now choose it for a chat trigger, and
            workflows can post there.
          </Text>
          <Group justify="flex-end">
            <Button onClick={onClose}>Done</Button>
          </Group>
        </Stack>
      ) : code ? (
        <Stack gap="md">
          <Step number={1} title="Invite the bot first">
            <Text size="sm" c="dimmed">
              The bot only sees the channels it is in.
            </Text>
            {provider === 'slack' ? (
              <Group gap="xs" wrap="nowrap">
                <Code>{code.invite}</Code>
                <CopyButton value={code.invite}>
                  {({ copied, copy }) => (
                    <Tooltip label={copied ? 'Copied' : 'Copy'}>
                      <ActionIcon variant="subtle" size="sm" color="gray" onClick={copy} aria-label="Copy the invite">
                        {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                      </ActionIcon>
                    </Tooltip>
                  )}
                </CopyButton>
              </Group>
            ) : (
              <Text size="sm">{code.invite}.</Text>
            )}
          </Step>

          <Step
            number={2}
            title={
              code.mention ? (
                <>
                  In the channel, type <Code>{code.mention}</Code> and pick it from the list, then paste:
                </>
              ) : (
                'In the channel, mention the bot and pick it from the list, then paste:'
              )
            }
          >
            <Group gap="xs" wrap="nowrap">
              <TextInput
                value={code.command ?? ''}
                readOnly
                aria-label="Message to post"
                style={{ flex: 1 }}
                styles={{ input: { fontFamily: 'JetBrains Mono, monospace' } }}
              />
              <CopyButton value={code.command ?? ''}>
                {({ copied, copy }) => (
                  <Tooltip label={copied ? 'Copied' : 'Copy'}>
                    <ActionIcon variant="default" size="lg" onClick={copy} aria-label="Copy the message">
                      {copied ? <IconCheck size={16} /> : <IconCopy size={16} />}
                    </ActionIcon>
                  </Tooltip>
                )}
              </CopyButton>
            </Group>
            <Text size="xs" c="dimmed">
              Pick the bot from the list as you type. A mention pasted as plain text does not reach the bot: Teams
              ignores a typed @name.
            </Text>
          </Step>

          {code.failure_reason && (
            <Alert color="yellow" variant="light" icon={<IconAlertCircle size={16} />}>
              The last attempt was refused: {code.failure_reason}
            </Alert>
          )}

          {code.state === 'expired' ? (
            <Stack gap="xs">
              <Text size="sm">This code has expired.</Text>
              <Group justify="flex-end">
                <Button variant="default" onClick={onClose}>
                  Close
                </Button>
                <Button onClick={issue}>Get a new code</Button>
              </Group>
            </Stack>
          ) : (
            <Stack gap="xs">
              <Group gap="xs" role="status">
                <Loader size="xs" />
                <Text size="sm" c="dimmed">
                  Waiting for the message · expires in {formatRemaining(Date.parse(code.expires_at) - now)}
                </Text>
              </Group>
              <Group justify="flex-end">
                <Button variant="default" onClick={onClose}>
                  Close
                </Button>
              </Group>
            </Stack>
          )}
        </Stack>
      ) : null}
    </Modal>
  );
};
