import { Head, router } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Checkbox,
  Code,
  CopyButton,
  Divider,
  Group,
  Stack,
  Text,
  Title,
  UnstyledButton,
} from '@mantine/core';
import { IconCheck, IconChevronRight, IconCopy, IconExternalLink } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { disableMCPTokenProfilePath, regenerateMCPTokenProfilePath, updateMCPToolsProfilePath } from 'shared/routes';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { ProfileTabs } from './ProfileTabs';

interface McpTool {
  name: string;
  description: string;
  readOnly: boolean;
}

interface McpToolGroup {
  tag: string;
  title: string;
  blurb: string | null;
  tools: McpTool[];
}

interface McpProps {
  enabled: boolean;
  lastUsedAt: string | null;
  serverUrl: string;
  serverName: string;
  token: string | null;
  toolGroups: McpToolGroup[];
  // null means "every tool, including ones added later" — see
  // Tools::PersonalMCP.update_selection!.
  enabledTools: string[] | null;
}

interface Props {
  mcp: McpProps;
}

const sorted = (names: Iterable<string>) => [...names].sort();
const sameSelection = (a: string[], b: string[]) => a.length === b.length && a.every((n, i) => n === b[i]);

// Cursor installs a server from a deeplink whose `config` is the base64 of the
// server entry alone (no name wrapper) — the same object that would sit under
// the server's key in mcp.json.
const clientConfig = (serverUrl: string, token: string) => ({
  url: serverUrl,
  headers: { Authorization: `Bearer ${token}` },
});

const cursorInstallLink = (serverName: string, serverUrl: string, token: string) => {
  const config = btoa(JSON.stringify(clientConfig(serverUrl, token)));
  return `cursor://anysphere.cursor-deeplink/mcp/install?name=${encodeURIComponent(serverName)}&config=${encodeURIComponent(config)}`;
};

function CopyAction({ value, label }: { value: string; label: string }) {
  return (
    <CopyButton value={value}>
      {({ copied, copy }) => (
        <Button
          variant="subtle"
          size="compact-xs"
          onClick={copy}
          leftSection={copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
        >
          {copied ? 'Copied' : label}
        </Button>
      )}
    </CopyButton>
  );
}

// The token exists in the UI exactly once, right after it is generated: the
// server keeps only a digest. Everything a client needs is therefore built and
// offered here — after a reload the only way back is a new token.
function ConnectionSection({ mcp }: { mcp: McpProps }) {
  const claudeCommand = mcp.token
    ? `claude mcp add ${mcp.serverName} --transport http ${mcp.serverUrl} --header "Authorization: Bearer ${mcp.token}"`
    : null;
  const jsonConfig = mcp.token
    ? JSON.stringify({ mcpServers: { [mcp.serverName]: clientConfig(mcp.serverUrl, mcp.token) } }, null, 2)
    : null;

  return (
    <Card p={24}>
      <Title order={4} mb={4}>
        Personal MCP
      </Title>
      <Text fz={14} c="dimmed" mb="md">
        Connect your AI agent (Claude Code, Cursor, ...) to Aixle Flow: list your projects, manage board tasks and build
        workflows — with exactly your access level.
      </Text>

      <Group gap={8} mb="md">
        <StatusBadge tone={mcp.enabled ? 'success' : 'neutral'}>{mcp.enabled ? 'Enabled' : 'Disabled'}</StatusBadge>
        {mcp.enabled && <StatusBadge tone="neutral">{mcp.lastUsedAt ? 'In use' : 'Not used yet'}</StatusBadge>}
      </Group>

      {mcp.token && (
        <Box mb="md">
          <Group justify="space-between" align="center" wrap="nowrap" gap="sm">
            <Text fz={14} fw={600} c="var(--app-text-primary)">
              Your token — copy it now, it will not be shown again:
            </Text>
            {/* This is the only moment the token exists in the UI, so it needs a
                copy affordance, not a select-the-text-yourself code block. */}
            <CopyButton value={mcp.token}>
              {({ copied, copy }) => (
                <Button
                  variant={copied ? 'light' : 'filled'}
                  size="compact-sm"
                  onClick={copy}
                  leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                >
                  {copied ? 'Copied' : 'Copy token'}
                </Button>
              )}
            </CopyButton>
          </Group>
          <Code block my={8} data-testid="mcp-token">
            {mcp.token}
          </Code>

          <Group justify="space-between" align="center" wrap="nowrap" gap="sm" mt="md">
            <Text fz={13} c="dimmed">
              Add to Cursor:
            </Text>
            {/* The deeplink carries the token, so it only works while this page
                still holds one — hence the button lives beside the token, not
                on the always-visible part of the page. */}
            <Group gap={4} wrap="nowrap">
              <Button
                component="a"
                href={cursorInstallLink(mcp.serverName, mcp.serverUrl, mcp.token)}
                variant="light"
                size="compact-sm"
                leftSection={<IconExternalLink size={14} />}
              >
                Add to Cursor
              </Button>
              <CopyAction value={jsonConfig ?? ''} label="Copy JSON" />
            </Group>
          </Group>

          <Group justify="space-between" align="center" wrap="nowrap" gap="sm" mt="md">
            <Text fz={13} c="dimmed" mb={4}>
              Add to Claude Code:
            </Text>
            <CopyAction value={claudeCommand ?? ''} label="Copy command" />
          </Group>
          <Code block data-testid="mcp-claude-command">
            {claudeCommand}
          </Code>
        </Box>
      )}

      {mcp.enabled && !mcp.token && (
        <Text fz={13} c="dimmed" mb="md">
          MCP access is enabled.
          {mcp.lastUsedAt ? ` Last used ${new Date(mcp.lastUsedAt).toLocaleString()}.` : ' Not used yet.'}
        </Text>
      )}

      <Group gap="sm">
        <Button
          variant={mcp.enabled ? 'default' : 'filled'}
          onClick={() => router.post(regenerateMCPTokenProfilePath(), {}, { preserveScroll: true })}
        >
          {mcp.enabled ? 'Regenerate token' : 'Enable MCP'}
        </Button>
        {mcp.enabled && (
          <Button
            variant="subtle"
            color="red"
            onClick={() => router.delete(disableMCPTokenProfilePath(), { preserveScroll: true })}
          >
            Disable
          </Button>
        )}
      </Group>
    </Card>
  );
}

function ToolsSection({ mcp }: { mcp: McpProps }) {
  const allNames = useMemo(() => mcp.toolGroups.flatMap((g) => g.tools.map((t) => t.name)), [mcp.toolGroups]);
  const [selected, setSelected] = useState<Set<string>>(() => new Set(mcp.enabledTools ?? allNames));
  const [baseline, setBaseline] = useState<string[]>(() => sorted(mcp.enabledTools ?? allNames));
  const [saving, setSaving] = useState(false);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const dirty = !sameSelection(sorted(selected), baseline);

  const toggleGroup = (tag: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (!next.delete(tag)) next.add(tag);
      return next;
    });

  const setNames = (names: string[], on: boolean) =>
    setSelected((prev) => {
      const next = new Set(prev);
      names.forEach((n) => (on ? next.add(n) : next.delete(n)));
      return next;
    });

  const save = () => {
    setSaving(true);
    // Sending every name is how "all" is expressed: the server stores that as
    // NULL, which keeps tools added in a later release switched on.
    router.patch(
      updateMCPToolsProfilePath(),
      { toolNames: [...selected] },
      {
        preserveScroll: true,
        onSuccess: () => setBaseline(sorted(selected)),
        onFinish: () => setSaving(false),
      },
    );
  };

  return (
    <Card p={24} mt={16}>
      <Group justify="space-between" align="flex-start" wrap="nowrap" gap="sm">
        <Box>
          <Title order={4} mb={4}>
            Tools
          </Title>
          <Text fz={14} c="dimmed">
            Which tools this server offers your agent. Switching the ones you never use off keeps them out of the
            agent&apos;s context — it is not a permission boundary: the token always runs as you, with your access
            level.
          </Text>
        </Box>
        <Badge variant="light" size="lg" style={{ flexShrink: 0 }}>
          {selected.size} / {allNames.length}
        </Badge>
      </Group>

      <Group gap="xs" mt="md">
        <Button variant="default" size="compact-xs" onClick={() => setNames(allNames, true)}>
          Select all
        </Button>
        <Button variant="default" size="compact-xs" onClick={() => setNames(allNames, false)}>
          Clear
        </Button>
      </Group>

      <Divider my="md" />

      {/* Groups start collapsed and their rows are only mounted while open —
          the real registry is ~85 tools, and rendering every checkbox at once
          turns this card into most of the page. */}
      <Stack gap="xs">
        {mcp.toolGroups.map((group) => {
          const names = group.tools.map((t) => t.name);
          const on = names.filter((n) => selected.has(n)).length;
          const isOpen = expanded.has(group.tag);

          return (
            <Card key={group.tag} withBorder p={0}>
              <UnstyledButton onClick={() => toggleGroup(group.tag)} aria-expanded={isOpen} w="100%" px="md" py="sm">
                <Group justify="space-between" wrap="nowrap" gap="sm">
                  <Group gap={8} wrap="nowrap">
                    <IconChevronRight
                      size={14}
                      style={{ transform: isOpen ? 'rotate(90deg)' : undefined, flexShrink: 0 }}
                    />
                    <Text fw={600} fz={14}>
                      {group.title}
                    </Text>
                  </Group>
                  <Text fz={12} c="dimmed">
                    {on} / {names.length}
                  </Text>
                </Group>
              </UnstyledButton>

              {isOpen && (
                <Box px="md" pb="md">
                  {group.blurb && (
                    <Text fz={12} c="dimmed" mb="sm">
                      {group.blurb}
                    </Text>
                  )}
                  <Group gap="xs" mb="sm">
                    <Button variant="subtle" size="compact-xs" onClick={() => setNames(names, true)}>
                      All
                    </Button>
                    <Button variant="subtle" size="compact-xs" onClick={() => setNames(names, false)}>
                      None
                    </Button>
                  </Group>
                  <Stack gap="xs">
                    {group.tools.map((tool) => (
                      <Checkbox
                        key={tool.name}
                        label={tool.name}
                        // Appended to the description rather than badged next to
                        // the label: the label is the checkbox's accessible name,
                        // and it should stay exactly the tool the agent calls.
                        description={tool.readOnly ? tool.description : `${tool.description} · writes`}
                        checked={selected.has(tool.name)}
                        onChange={(e) => setNames([tool.name], e.currentTarget.checked)}
                      />
                    ))}
                  </Stack>
                </Box>
              )}
            </Card>
          );
        })}
      </Stack>

      <Group mt="md" gap="sm">
        <Button onClick={save} disabled={!dirty || saving} loading={saving}>
          Save tools
        </Button>
        {dirty && (
          <Text fz={12} c="dimmed">
            Unsaved changes. A connected client picks them up on its next connection.
          </Text>
        )}
      </Group>
    </Card>
  );
}

function ProfileMcpPage({ mcp }: Props) {
  return (
    <AuthLayout>
      <Head title="Personal MCP" />
      <Box maw={1120} mx="auto">
        <Title order={1} fz={28} fw={600} c="var(--app-text-primary)" mb={4}>
          My Profile
        </Title>
        {/* Unlike the account tab, none of this is per company: the token is the
            user, and it reaches every company they belong to. */}
        <Text size="sm" c="dimmed" mb={24}>
          Your personal MCP token works across every company you belong to.
        </Text>

        <ProfileTabs active="mcp" />

        <ConnectionSection mcp={mcp} />
        <ToolsSection mcp={mcp} />
      </Box>
    </AuthLayout>
  );
}

export default ProfileMcpPage;
