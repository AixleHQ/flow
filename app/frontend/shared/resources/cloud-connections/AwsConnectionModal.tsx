import {
  Alert,
  Anchor,
  Badge,
  Button,
  Code,
  Group,
  Loader,
  Modal,
  Select,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { useCallback, useEffect, useRef, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import {
  apiV1CloudAwsConnectionPath,
  completeApiV1CloudAwsConnectionPath,
  pollApiV1CloudAwsConnectionPath,
} from 'shared/routes';

/**
 * Connect an AWS account so a developer's tokens are billed to it.
 *
 * Three paths, defaulting to the one the design doc ranks first: a role the customer's
 * admin creates (a reviewable IAM object, no browser flow), Identity Center sign-in (for
 * developers with no IAM rights), or an existing key/gateway.
 *
 * For the Identity Center path the whole OIDC exchange happens server-side; this component
 * only collects the Start URL, shows the verification link, polls, and lets the user pick
 * an account and role. That verification URL is rendered exactly as the backend returned
 * it and must never be constructed or rewritten here — the documented
 * device.sso.<region> host does not resolve, and real instances return per-instance
 * portal hosts.
 */

type Account = { account_id: string; account_name: string; roles: string[] };

type Phase = 'form' | 'waiting' | 'select' | 'saving';

const DEFAULT_BEDROCK_REGION = 'us-east-1';
const DEFAULT_PROFILE = 'aixle-bedrock';
const FALLBACK_POLL_SECONDS = 5;

export interface AwsConnectionModalProps {
  opened: boolean;
  onClose: () => void;
  onConnected?: () => void;
  /** Render the body only, for hosting inside a modal that is already open. */
  embedded?: boolean;
}

export function AwsConnectionModal({ opened, onClose, onConnected, embedded = false }: AwsConnectionModalProps) {
  const [phase, setPhase] = useState<Phase>('form');
  const [startUrl, setStartUrl] = useState('');
  const [ssoRegion, setSsoRegion] = useState('');
  const [region, setRegion] = useState(DEFAULT_BEDROCK_REGION);
  const [profile, setProfile] = useState(DEFAULT_PROFILE);
  const [handle, setHandle] = useState<string | null>(null);
  const [verificationUrl, setVerificationUrl] = useState<string | null>(null);
  const [userCode, setUserCode] = useState<string | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [accountId, setAccountId] = useState<string | null>(null);
  const [roleName, setRoleName] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Polling must stop when the modal closes or unmounts, otherwise a dead flow keeps
  // hitting the API from a component nobody can see.
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const stopPolling = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const reset = useCallback(() => {
    stopPolling();
    setPhase('form');
    setHandle(null);
    setVerificationUrl(null);
    setUserCode(null);
    setAccounts([]);
    setAccountId(null);
    setRoleName(null);
    setError(null);
  }, [stopPolling]);

  useEffect(() => {
    if (!opened) reset();
    return stopPolling;
  }, [opened, reset, stopPolling]);

  const poll = useCallback(async (flowHandle: string) => {
    const res = await apiFetch(pollApiV1CloudAwsConnectionPath(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ handle: flowHandle }),
    });

    // 410 means the authorization died; the same handle can never succeed, so start over
    // rather than polling a corpse.
    if (res.status === 410) {
      setError('The sign-in request expired. Start again.');
      setPhase('form');
      return;
    }
    if (!res.ok) {
      setError('Could not check the sign-in status.');
      setPhase('form');
      return;
    }

    const body = await res.json();
    if (body.status === 'pending') {
      const seconds = Number(body.interval) || FALLBACK_POLL_SECONDS;
      timer.current = setTimeout(() => void poll(flowHandle), seconds * 1000);
      return;
    }

    const granted: Account[] = body.accounts ?? [];
    setAccounts(granted);
    if (granted.length === 1) {
      setAccountId(granted[0].account_id);
      if (granted[0].roles.length === 1) setRoleName(granted[0].roles[0]);
    }
    setPhase('select');
  }, []);

  const start = async () => {
    setError(null);
    const res = await apiFetch(apiV1CloudAwsConnectionPath(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ start_url: startUrl, sso_region: ssoRegion }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.message ?? 'Could not start the sign-in.');
      return;
    }

    const body = await res.json();
    setHandle(body.handle);
    setVerificationUrl(body.verification_url);
    setUserCode(body.user_code);
    setPhase('waiting');
    void poll(body.handle);
  };

  const complete = async () => {
    if (!handle || !accountId || !roleName) return;

    setPhase('saving');
    setError(null);
    const res = await apiFetch(completeApiV1CloudAwsConnectionPath(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ handle, account_id: accountId, role_name: roleName, region, profile }),
    });
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      setError(body.message ?? 'Could not save the connection.');
      setPhase('select');
      return;
    }

    onConnected?.();
    onClose();
  };

  const selectedAccount = accounts.find((a) => a.account_id === accountId);

  const body = (
    <Stack gap="md">
      <>
        {error && (
          <Alert color="red" role="alert">
            {error}
          </Alert>
        )}

        {phase === 'form' && (
          <>
            <Text size="sm" c="dimmed">
              Sign in to your organisation&apos;s AWS IAM Identity Center. Your tokens are billed to your own AWS
              account; Aixle never sees your prompts.
            </Text>
            <TextInput
              label="Start URL"
              description="From your AWS access portal invite, e.g. https://d-xxxxxxxxxx.awsapps.com/start"
              placeholder="https://d-xxxxxxxxxx.awsapps.com/start"
              value={startUrl}
              onChange={(e) => setStartUrl(e.currentTarget.value)}
            />
            <TextInput
              label="Identity Center region"
              description="The region your Identity Center instance lives in — it may differ from the region you run Bedrock in."
              placeholder="us-west-2"
              value={ssoRegion}
              onChange={(e) => setSsoRegion(e.currentTarget.value)}
            />
            <Group justify="flex-end">
              <Button onClick={() => void start()} disabled={!startUrl.trim() || !ssoRegion.trim()}>
                Continue
              </Button>
            </Group>
          </>
        )}

        {phase === 'waiting' && verificationUrl && (
          <>
            <Text size="sm">Open the link below and approve the request. This page will continue on its own.</Text>
            <Button component="a" href={verificationUrl} target="_blank" rel="noreferrer noopener">
              Approve in AWS
            </Button>
            <Text size="sm" c="dimmed">
              The link already carries your code. If AWS asks for it, it is <Code>{userCode}</Code>.
            </Text>
            <Group gap="xs">
              <Loader size="xs" />
              <Text size="sm" c="dimmed">
                Waiting for approval…
              </Text>
            </Group>
          </>
        )}

        {(phase === 'select' || phase === 'saving') && (
          <>
            {accounts.length === 0 ? (
              <Alert color="yellow">
                Your sign-in worked, but this Identity Center grants you no accounts. Ask your administrator for a
                permission set with Bedrock access.
              </Alert>
            ) : (
              <>
                <Badge color="green" variant="light" w="fit-content">
                  Signed in
                </Badge>
                <Select
                  label="AWS account"
                  data={accounts.map((a) => ({
                    value: a.account_id,
                    label: a.account_name ? `${a.account_name} (${a.account_id})` : a.account_id,
                  }))}
                  value={accountId}
                  onChange={(value) => {
                    setAccountId(value);
                    const next = accounts.find((a) => a.account_id === value);
                    setRoleName(next && next.roles.length === 1 ? next.roles[0] : null);
                  }}
                />
                <Select
                  label="Permission set"
                  data={(selectedAccount?.roles ?? []).map((r) => ({ value: r, label: r }))}
                  value={roleName}
                  onChange={setRoleName}
                  disabled={!selectedAccount}
                />
                <TextInput
                  label="Bedrock region"
                  description="Where model requests are sent. Often different from the Identity Center region."
                  value={region}
                  onChange={(e) => setRegion(e.currentTarget.value)}
                />
                <TextInput
                  label="AWS profile name"
                  description="Only change this if a repo you work in commits its own .claude/settings.json pinning AWS_PROFILE — the name has to match, or Claude Code looks for a profile that does not exist."
                  value={profile}
                  onChange={(e) => setProfile(e.currentTarget.value)}
                />
                <Group justify="flex-end">
                  <Button
                    onClick={() => void complete()}
                    loading={phase === 'saving'}
                    disabled={!accountId || !roleName || !region.trim() || !profile.trim()}
                  >
                    Connect
                  </Button>
                </Group>
              </>
            )}
          </>
        )}

        <Text size="xs" c="dimmed">
          Aixle stores a refresh token so your sessions can mint short-lived credentials. Identity Center caps this at
          90 days, after which you sign in again. Remove the connection any time from your profile.{' '}
          <Anchor
            href="https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html"
            target="_blank"
            rel="noreferrer"
          >
            About Identity Center
          </Anchor>
        </Text>
      </>
    </Stack>
  );

  // Rendered inline when it lives inside another modal — the auth session's own modal is
  // already on screen when Claude Code's wizard asks for credentials, and stacking modals
  // there would trap focus in the wrong one.
  return embedded ? (
    body
  ) : (
    <Modal opened={opened} onClose={onClose} title="Connect AWS Bedrock" size="lg">
      {body}
    </Modal>
  );
}
