import { Anchor, Button, Group, Paper, Stack, Text } from '@mantine/core';
import { useState, useSyncExternalStore } from 'react';

import { consentPending, setConsent, subscribe } from 'shared/lib/analytics';
import { legalPrivacyPolicyPath } from 'shared/routes';

/**
 * Asks once whether product analytics may run. Shown wherever the server shares an
 * analytics config and nobody has answered yet; a browser's Do Not Track or Global
 * Privacy Control answers "no" by itself, so it is never shown there.
 */
export function AnalyticsConsentBanner() {
  const pending = useSyncExternalStore(subscribe, consentPending, () => false);
  const [saving, setSaving] = useState(false);
  if (!pending) return null;

  const answer = (choice: 'granted' | 'denied') => {
    setSaving(true);
    void setConsent(choice).finally(() => setSaving(false));
  };

  return (
    <Paper
      role="dialog"
      aria-labelledby="analytics-consent-title"
      data-ph-unmask
      shadow="md"
      withBorder
      p="md"
      maw={520}
      style={{ position: 'fixed', bottom: 16, left: 16, right: 16, zIndex: 300, marginInline: 'auto' }}
    >
      <Stack gap="xs">
        <Text id="analytics-consent-title" fw={600}>
          We use analytics to improve Aixle Flow
        </Text>
        <Text size="sm" c="dimmed">
          With your permission, we collect how you use the app — pages visited, clicks, and session recordings — to find
          what&apos;s confusing and fix it. Text on screen, anything you type, your code, agent output and secrets are
          hidden from recordings. You can change this anytime in Profile → Privacy.{' '}
          <Anchor href={legalPrivacyPolicyPath()} size="sm" target="_blank" rel="noopener">
            Privacy Policy
          </Anchor>
        </Text>
        <Group justify="flex-end" gap="xs">
          <Button variant="default" onClick={() => answer('denied')} disabled={saving}>
            Decline
          </Button>
          <Button variant="default" onClick={() => answer('granted')} disabled={saving}>
            Accept
          </Button>
        </Group>
      </Stack>
    </Paper>
  );
}
