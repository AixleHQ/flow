import { router } from '@inertiajs/react';
import {
  ActionIcon,
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

const schema = z
  .object({
    name: z
      .string()
      .min(1, 'Name is required')
      .regex(/^[a-z][a-z0-9_-]*$/, 'Must start with letter, use lowercase, numbers, dashes, underscores'),
    displayName: z.string().min(1, 'Display name is required'),
    transport: z.enum(['http', 'sse', 'stdio']),
    url: z.string().default(''),
    command: z.string().default(''),
    description: z.string().optional(),
    enabled: z.boolean().default(true),
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
  displayName: string;
  url: string | null;
  transport: string;
  headers: Record<string, string> | null;
  command: string | null;
  env: Record<string, string> | null;
  description: string | null;
  enabled: boolean;
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
  const isEdit = !!editServer;

  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: {
      name: '',
      displayName: '',
      transport: 'http',
      url: '',
      command: '',
      description: '',
      enabled: true,
    },
  });

  const transport = form.values.transport;
  const isStdio = transport === 'stdio';

  useEffect(() => {
    if (opened) {
      if (editServer) {
        const headers = editServer.headers ?? {};
        setHeadersList(Object.entries(headers).map(([key, value]) => ({ key, value: String(value) })));
        const env = editServer.env ?? {};
        setEnvList(Object.entries(env).map(([key, value]) => ({ key, value: String(value) })));
        form.setValues({
          name: editServer.name,
          displayName: editServer.displayName,
          transport: editServer.transport as 'http' | 'sse' | 'stdio',
          url: editServer.url ?? '',
          command: editServer.command ?? '',
          description: editServer.description ?? '',
          enabled: editServer.enabled,
        });
      } else {
        setHeadersList([]);
        setEnvList([]);
        form.reset();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, editServer]);

  const kvToObj = (list: KVPair[]) => {
    const obj: Record<string, string> = {};
    list.forEach(({ key, value }) => {
      if (key.trim()) obj[key.trim()] = value;
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
            placeholder="playwright"
            {...form.getInputProps('name')}
            description="Lowercase identifier (e.g., playwright, context7)"
            disabled={isEdit}
          />

          <TextInput label="Display Name" placeholder="Playwright Browser" {...form.getInputProps('displayName')} />

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
              <TextInput
                label="URL"
                placeholder="https://mcp.example.com"
                {...form.getInputProps('url')}
                description="MCP server endpoint URL"
              />

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
