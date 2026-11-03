import { Head } from '@inertiajs/react';
import { Box, Paper, Switch, Text, Title } from '@mantine/core';
import { useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { setConsent } from 'shared/lib/analytics';
import type { AnalyticsConsent } from 'shared/ui/types';

import { ProfileTabs } from './ProfileTabs';

interface Props {
  analyticsConsent: AnalyticsConsent | null;
  analyticsAvailable: boolean;
}

export default function Privacy({ analyticsConsent, analyticsAvailable }: Props) {
  const [granted, setGranted] = useState(analyticsConsent === 'granted');
  const [saving, setSaving] = useState(false);

  const change = (next: boolean) => {
    setGranted(next);
    setSaving(true);
    void setConsent(next ? 'granted' : 'denied').finally(() => setSaving(false));
  };

  return (
    <AuthLayout>
      <Head title="Privacy" />
      <Box maw={1120} mx="auto">
        <Title order={1} fz={28} fw={600} c="var(--app-text-primary)" mb={24}>
          My Profile
        </Title>
        <ProfileTabs active="privacy" />

        <Paper withBorder p="lg" maw={640}>
          <Switch
            label="Product analytics"
            description="Share usage data and session recordings to help us improve Aixle Flow. Text on screen, inputs, code, agent output and secrets are always hidden. Turning this off stops collection on all your devices."
            checked={granted}
            disabled={saving || !analyticsAvailable}
            onChange={(event) => change(event.currentTarget.checked)}
          />
          {!analyticsAvailable && (
            <Text size="sm" c="dimmed" mt="sm">
              This installation does not collect product analytics.
            </Text>
          )}
        </Paper>
      </Box>
    </AuthLayout>
  );
}
