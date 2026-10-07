import { router, usePage } from '@inertiajs/react';
import { Box, Tabs, Text } from '@mantine/core';

import { companySettingsAccessPath, companySettingsBillingPath, companySettingsPath } from 'shared/routes';
import type { SharedPermissions } from 'shared/ui';

export type SettingsTab = 'general' | 'access' | 'billing';

const TAB_PATHS: Record<SettingsTab, () => string> = {
  general: companySettingsPath,
  access: companySettingsAccessPath,
  billing: companySettingsBillingPath,
};

// Each tab is its own page, not a client-side panel swap. The two halves of
// company settings save differently — General is one form behind one Save,
// Access applies every control on the spot — and a tab that is also a URL keeps
// that difference honest: leaving one cannot silently drop the other's state,
// and either can be linked to directly.
export function SettingsTabs({
  active,
  companyName,
  children,
}: {
  active: SettingsTab;
  companyName: string;
  children: React.ReactNode;
}) {
  const { permissions } = usePage<{ permissions?: SharedPermissions }>().props;

  return (
    <Box px="lg" py="md">
      <Text component="p" fz="xl" fw={600} m={0}>
        Company Settings
      </Text>
      <Text component="p" c="dimmed" fz="sm" mt={4} mb="md">
        How {companyName} looks, how much it may run at once, and how people get in.
      </Text>

      <Tabs value={active} onChange={(value) => value !== active && router.visit(TAB_PATHS[value as SettingsTab]())}>
        <Tabs.List mb="lg">
          <Tabs.Tab value="general">General</Tabs.Tab>
          <Tabs.Tab value="access">Access</Tabs.Tab>
          {permissions?.canManageBilling && <Tabs.Tab value="billing">Billing</Tabs.Tab>}
        </Tabs.List>
      </Tabs>

      {children}
    </Box>
  );
}
