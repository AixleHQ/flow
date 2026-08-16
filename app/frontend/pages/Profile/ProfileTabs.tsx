import { router } from '@inertiajs/react';
import { Tabs } from '@mantine/core';

import { mcpProfilePath, profilePath, usageProfilePath } from 'shared/routes';

export type ProfileTab = 'account' | 'usage' | 'mcp';

const TAB_PATHS: Record<ProfileTab, () => string> = {
  account: profilePath,
  usage: usageProfilePath,
  mcp: mcpProfilePath,
};

// One tab bar for the three profile pages. Each tab is a full page visit — they
// are separate Inertia pages, not panels — so the bar has to be rendered by
// every one of them or the user lands somewhere with no way back.
export function ProfileTabs({ active }: { active: ProfileTab }) {
  return (
    <Tabs
      value={active}
      onChange={(value) => {
        if (value && value !== active) router.visit(TAB_PATHS[value as ProfileTab]());
      }}
      mb="lg"
    >
      <Tabs.List>
        <Tabs.Tab value="account">Account</Tabs.Tab>
        <Tabs.Tab value="usage">Usage</Tabs.Tab>
        <Tabs.Tab value="mcp">MCP</Tabs.Tab>
      </Tabs.List>
    </Tabs>
  );
}
