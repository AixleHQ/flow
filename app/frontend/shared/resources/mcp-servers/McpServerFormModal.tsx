import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Anchor,
  Badge,
  Box,
  Button,
  Group,
  Modal,
  NativeSelect,
  Stack,
  Switch,
  Text,
  TextInput,
  Textarea,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { IconPlus, IconTrash } from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

import { ConfigItemValueField } from './ConfigItemValueField';

// The MCPServerResource masks every stored header/env value to a sentinel before it reaches the
// browser. The modal echoes that sentinel back untouched for values the user didn't edit; the
// backend swaps each sentinel for the stored secret (see McpServersController#unmask_secrets!), so
// the modal itself no longer needs to know the sentinel string.

type OauthStatus = 'pending' | 'active' | 'expiring' | 'error';

// Maps the per-user oauth_status from the resource to a connection badge (functional labels, not
// colours-only, so the state is legible without relying on hue).
const OAUTH_STATUS_META: Record<OauthStatus, { color: string; label: string }> = {
  active: { color: 'green', label: 'Connected' },
  expiring: { color: 'yellow', label: 'Expiring soon' },
  pending: { color: 'gray', label: 'Not connected' },
  error: { color: 'red', label: 'Reconnect' },
};

const schema = z
  .object({
    name: z.string().min(1, 'Name is required'),
    transport: z.enum(['http', 'sse', 'stdio']),
    url: z.string().default(''),
    command: z.string().default(''),
    description: z.string().optional(),
    enabled: z.boolean().default(true),
    authType: z.enum(['none', 'static', 'oauth']).default('none'),
    credentialScope: z.enum(['shared', 'per_user']).default('shared'),
  })
  .superRefine((data, ctx) => {
    if (data.transport === 'stdio') {
      if (!data.command?.trim()) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'Command is required for stdio transport',
          path: ['command'],
        });
      }
    } else {
      if (!data.url?.trim()) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'URL is required', path: ['url'] });
      } else {
        try {
          new URL(data.url);
        } catch {
          ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Must be a valid URL', path: ['url'] });
        }
      }
    }
  });

type FormData = z.infer<typeof schema>;

interface KVPair {
  key: string;
  value: string;
}

interface McpServer {
  id: number;
  name: string;
  url: string | null;
  transport: string;
  headers: Record<string, string> | null;
  command: string | null;
  env: Record<string, string> | null;
  description: string | null;
  enabled: boolean;
  // OAuth fields (optional so the list's richer McpServer type stays assignable). The resource
  // always sends auth_type/credential_scope; oauth_status is read-only and per-current-user.
  authType?: 'none' | 'static' | 'oauth';
  credentialScope?: 'shared' | 'per_user';
  oauthStatus?: OauthStatus | null;
}

interface McpServerFormModalProps {
  opened: boolean;
  onClose: () => void;
  editServer?: McpServer | null;
  configItemNames: string[];
  basePath: string;
}

export const McpServerFormModal: FC<McpServerFormModalProps> = ({
  opened,
  onClose,
  editServer,
  configItemNames,
  basePath,
}) => {
  const [loading, setLoading] = useState(false);
  const [headersList, setHeadersList] = useState<KVPair[]>([]);
  const [envList, setEnvList] = useState<KVPair[]>([]);
  // Credential scope defaults to project-wide (shared); the per-user option is tucked behind an
  // "Advanced" disclosure. Auto-expanded when editing a server that already uses per_user.
  const [showScopeOptions, setShowScopeOptions] = useState(false);
  const isEdit = !!editServer;

  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: {
      name: '',
      transport: 'http',
      url: '',
      command: '',
      description: '',
      enabled: true,
      authType: 'none',
      credentialScope: 'shared',
    },
  });

  const transport = form.values.transport;
  const isStdio = transport === 'stdio';
  const isOauth = form.values.authType === 'oauth';
  // oauth_status is read-only (never a form value); read it straight off the edited server. A saved
  // oauth server with no credential yet reports "pending".
  const oauthStatus: OauthStatus = editServer?.oauthStatus ?? 'pending';
  const statusMeta = OAUTH_STATUS_META[oauthStatus] ?? OAUTH_STATUS_META.pending;

  // OAuth requires a top-level browser navigation (the authorize entry redirects off-site), so this
  // is window.location, NOT an Inertia router visit. Connect needs a persisted mcp_server_id.
  const handleConnect = () => {
    if (!editServer) return;
    window.location.href = `/oauth/mcp/${editServer.id}/connect?return_to=${encodeURIComponent(basePath)}`;
  };

  useEffect(() => {
    if (opened) {
      if (editServer) {
        const headers = editServer.headers ?? {};
        setHeadersList(Object.entries(headers).map(([key, value]) => ({ key, value: String(value) })));
        const env = editServer.env ?? {};
        setEnvList(Object.entries(env).map(([key, value]) => ({ key, value: String(value) })));
        form.setValues({
          name: editServer.name,
          transport: editServer.transport as 'http' | 'sse' | 'stdio',
          url: editServer.url ?? '',
          command: editServer.command ?? '',
          description: editServer.description ?? '',
          enabled: editServer.enabled,
          authType: editServer.authType ?? 'none',
          credentialScope: editServer.credentialScope ?? 'shared',
        });
        // Reveal the advanced scope control up-front only when it's already non-default.
        setShowScopeOptions(editServer.credentialScope === 'per_user');
      } else {
        setHeadersList([]);
        setEnvList([]);
        setShowScopeOptions(false);
        form.reset();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, editServer]);

  const kvToObj = (list: KVPair[]) => {
    const obj: Record<string, string> = {};
    list.forEach(({ key, value }) => {
      if (!key.trim()) return;
      // Send EVERY current key, keeping the mask sentinel for values the user never edited. The
      // server swaps each sentinel back to the stored secret, so untouched secrets are preserved
      // while keys the user removed (absent here) stay removed. Sending only edited values would be
      // ambiguous — the backend couldn't tell "unchanged" from "deleted" and would wipe untouched
      // secrets on every edit.
      obj[key.trim()] = value;
    });
    return obj;
  };

  const handleSubmit = (values: FormData) => {
    setLoading(true);

    const payload = {
      mcpServer: {
        ...values,
        headers: isStdio ? {} : kvToObj(headersList),
        env: isStdio ? kvToObj(envList) : {},
      },
    };

    const opts = {
      preserveScroll: true,
      onFinish: () => setLoading(false),
      onSuccess: () => onClose(),
    };

    if (isEdit) {
      router.patch(`${basePath}/${editServer!.id}`, payload, opts);
    } else {
      router.post(basePath, payload, opts);
    }
  };

  const updateKVList = (
    list: KVPair[],
    setList: React.Dispatch<React.SetStateAction<KVPair[]>>,
    index: number,
    field: 'key' | 'value',
    value: string,
  ) => {
    const newList = [...list];
    newList[index][field] = value;
    setList(newList);
  };

  const removeKV = (list: KVPair[], setList: React.Dispatch<React.SetStateAction<KVPair[]>>, index: number) => {
    setList(list.filter((_, i) => i !== index));
  };

  return (
    <Modal opened={opened} onClose={onClose} title={isEdit ? 'Edit MCP Server' : 'Add MCP Server'} size="lg">
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          <TextInput
            label="Name"
            placeholder="Playwright Browser"
            {...form.getInputProps('name')}
            description={
              isEdit
                ? 'Locked after creation — agents reference the server by this name'
                : "Normalized to an agent identifier (e.g. 'Playwright Browser' → playwright_browser)"
            }
            disabled={isEdit}
          />

          <NativeSelect
            label="Transport"
            {...form.getInputProps('transport')}
            data={[
              { label: 'HTTP (Streamable HTTP)', value: 'http' },
              { label: 'SSE (Server-Sent Events)', value: 'sse' },
              { label: 'Stdio (Local Process)', value: 'stdio' },
            ]}
          />

          {!isStdio && (
            <>
              <NativeSelect
                label="Auth Type"
                {...form.getInputProps('authType')}
                description="How requests to this server are authenticated"
                data={[
                  { label: 'None', value: 'none' },
                  { label: 'Static (manual headers)', value: 'static' },
                  { label: 'OAuth 2.1', value: 'oauth' },
                ]}
              />

              {isOauth && (
                <Box>
                  <Group gap={6} align="baseline">
                    <Text fz={13} c="dimmed">
                      Shared by all project members.
                    </Text>
                    <Anchor component="button" type="button" fz={13} onClick={() => setShowScopeOptions((v) => !v)}>
                      {showScopeOptions ? 'Hide advanced' : 'Advanced'}
                    </Anchor>
                  </Group>
                  {showScopeOptions && (
                    <NativeSelect
                      mt="xs"
                      label="Credential Scope"
                      {...form.getInputProps('credentialScope')}
                      description="Shared: one project-wide connection (default). Per-user: each member connects their own account — use only for personal accounts."
                      data={[
                        { label: 'Shared (project-wide, default)', value: 'shared' },
                        { label: 'Per-user (each member connects their own)', value: 'per_user' },
                      ]}
                    />
                  )}
                </Box>
              )}

              <TextInput
                label="URL"
                placeholder="https://mcp.example.com"
                {...form.getInputProps('url')}
                description="MCP server endpoint URL"
              />

              {isOauth && (
                <Box>
                  <Text fz={14} fw={500} c="dimmed" mb={4}>
                    Connection
                  </Text>
                  {isEdit && editServer ? (
                    <Group gap="sm" align="center">
                      <Button variant="light" onClick={handleConnect}>
                        Connect
                      </Button>
                      <Badge color={statusMeta.color} variant="light" size="lg">
                        {statusMeta.label}
                      </Badge>
                    </Group>
                  ) : (
                    <Text fz={13} c="dimmed" fs="italic">
                      Save first, then Connect
                    </Text>
                  )}
                </Box>
              )}

              {!isOauth && (
                <Box>
                  <Group justify="space-between" mb={4}>
                    <Text fz={14} fw={500} c="dimmed">
                      Headers
                    </Text>
                    <Button
                      variant="subtle"
                      size="compact-xs"
                      leftSection={<IconPlus size={14} />}
                      onClick={() => setHeadersList([...headersList, { key: '', value: '' }])}
                    >
                      Add Header
                    </Button>
                  </Group>

                  {headersList.length === 0 && (
                    <Text fz={13} c="dimmed" fs="italic" mb={4}>
                      No headers configured
                    </Text>
                  )}

                  <Stack gap="xs">
                    {headersList.map((header, i) => (
                      <Group key={i} gap="xs" align="flex-end">
                        <TextInput
                          label={i === 0 ? 'Key' : undefined}
                          size="sm"
                          value={header.key}
                          onChange={(e) => updateKVList(headersList, setHeadersList, i, 'key', e.currentTarget.value)}
                          placeholder="Authorization"
                          style={{ flex: 1 }}
                        />
                        <ConfigItemValueField
                          label={i === 0 ? 'Value' : undefined}
                          value={header.value}
                          onChange={(val) => updateKVList(headersList, setHeadersList, i, 'value', val)}
                          placeholder="Bearer token"
                          configItemNames={configItemNames}
                        />
                        <ActionIcon
                          variant="subtle"
                          color="red"
                          size="sm"
                          onClick={() => removeKV(headersList, setHeadersList, i)}
                        >
                          <IconTrash size={14} />
                        </ActionIcon>
                      </Group>
                    ))}
                  </Stack>
                </Box>
              )}
            </>
          )}

          {isStdio && (
            <>
              <TextInput
                label="Command"
                placeholder="npx @automattic/mcp-wordpress-remote"
                {...form.getInputProps('command')}
                description="Full command to run (e.g., npx @playwright/mcp --no-sandbox)"
                styles={{ input: { fontFamily: 'monospace' } }}
              />

              <Box>
                <Group justify="space-between" mb={4}>
                  <Text fz={14} fw={500} c="dimmed">
                    Environment Variables
                  </Text>
                  <Button
                    variant="subtle"
                    size="compact-xs"
                    leftSection={<IconPlus size={14} />}
                    onClick={() => setEnvList([...envList, { key: '', value: '' }])}
                  >
                    Add Variable
                  </Button>
                </Group>

                {envList.length === 0 && (
                  <Text fz={13} c="dimmed" fs="italic" mb={4}>
                    No environment variables configured
                  </Text>
                )}

                <Stack gap="xs">
                  {envList.map((envVar, i) => (
                    <Group key={i} gap="xs" align="flex-end">
                      <TextInput
                        label={i === 0 ? 'Key' : undefined}
                        size="sm"
                        value={envVar.key}
                        onChange={(e) => updateKVList(envList, setEnvList, i, 'key', e.currentTarget.value)}
                        placeholder="WP_API_URL"
                        styles={{ input: { fontFamily: 'monospace' } }}
                        style={{ flex: 1 }}
                      />
                      <ConfigItemValueField
                        label={i === 0 ? 'Value' : undefined}
                        value={envVar.value}
                        onChange={(val) => updateKVList(envList, setEnvList, i, 'value', val)}
                        placeholder="https://example.com"
                        configItemNames={configItemNames}
                      />
                      <ActionIcon
                        variant="subtle"
                        color="red"
                        size="sm"
                        onClick={() => removeKV(envList, setEnvList, i)}
                      >
                        <IconTrash size={14} />
                      </ActionIcon>
                    </Group>
                  ))}
                </Stack>
              </Box>
            </>
          )}

          <Textarea
            label="Description"
            placeholder={
              isStdio ? 'Browser automation via Playwright...' : 'Provides documentation lookup capabilities...'
            }
            {...form.getInputProps('description')}
            minRows={2}
            autosize
          />

          <Switch label="Enabled" {...form.getInputProps('enabled', { type: 'checkbox' })} />

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              {isEdit ? 'Save' : 'Create'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
