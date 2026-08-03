import { router } from '@inertiajs/react';
import { Alert, Badge, Button, Code, Group, Modal, Radio, Stack, Text } from '@mantine/core';
import { IconAlertTriangle, IconLock } from '@tabler/icons-react';
import { useEffect, useMemo, useState, type FC } from 'react';

import { ConfigItemValueField } from '../mcp-servers/ConfigItemValueField';

import type { Connector, ConnectorTarget } from './types';

interface ConnectorInstallModalProps {
  connector: Connector | null;
  basePath: string;
  onClose: () => void;
  /** Project secrets and variables, offered instead of typing a value inline. */
  configItemNames: string[];
}

const targetLabel = (target: ConnectorTarget): string => {
  if (target.kind === 'remote') return `Hosted endpoint (${target.transport})`;
  return `${target.registryType ?? 'package'} package${target.runtime ? ` via ${target.runtime}` : ''}`;
};

export const ConnectorInstallModal: FC<ConnectorInstallModalProps> = ({
  connector,
  basePath,
  onClose,
  configItemNames,
}) => {
  const installable = useMemo(() => connector?.targets.filter((t) => t.supported) ?? [], [connector]);
  const [targetId, setTargetId] = useState<string>('');
  const [values, setValues] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  const target = installable.find((t) => t.id === targetId) ?? installable[0];

  // Declared defaults pre-fill the form. They are deliberately NOT applied
  // server-side — a default is a suggestion the user can see and change here,
  // never a value written on their behalf.
  useEffect(() => {
    if (!connector) return;
    const first = installable[0];
    setTargetId(first?.id ?? '');
    setValues(
      Object.fromEntries((first?.inputs ?? []).filter((i) => i.default != null).map((i) => [i.key, String(i.default)])),
    );
  }, [connector, installable]);

  const selectTarget = (id: string) => {
    setTargetId(id);
    const next = installable.find((t) => t.id === id);
    setValues(
      Object.fromEntries((next?.inputs ?? []).filter((i) => i.default != null).map((i) => [i.key, String(i.default)])),
    );
  };

  const missingRequired = (target?.inputs ?? []).filter((i) => i.required && !values[i.key]?.trim());

  const submit = () => {
    if (!connector || !target) return;
    setSubmitting(true);
    router.post(
      basePath,
      { connector_name: connector.name, target_id: target.id, values },
      { onFinish: () => setSubmitting(false), onSuccess: onClose },
    );
  };

  const blockedReason = connector?.targets.find((t) => !t.supported)?.unsupportedReason;

  return (
    <Modal opened={!!connector} onClose={onClose} title={`Install ${connector?.pickerName ?? ''}`} size="lg">
      {connector && (
        <Stack gap="md">
          {connector.description && (
            <Text fz={13} c="dimmed">
              {connector.description}
            </Text>
          )}

          {connector.status === 'deprecated' && (
            <Alert color="yellow" icon={<IconAlertTriangle size={16} />}>
              This connector is marked deprecated in the registry.
            </Alert>
          )}

          {installable.length === 0 ? (
            <Alert color="gray" icon={<IconAlertTriangle size={16} />}>
              This connector offers no install option this platform can run.
              {blockedReason ? ` ${blockedReason}.` : ''}
            </Alert>
          ) : (
            <>
              {installable.length > 1 && (
                <Radio.Group label="Install option" value={targetId} onChange={selectTarget}>
                  <Stack gap="xs" mt="xs">
                    {installable.map((t) => (
                      <Radio key={t.id} value={t.id} label={targetLabel(t)} />
                    ))}
                  </Stack>
                </Radio.Group>
              )}

              {target?.kind === 'package' && (
                <Alert
                  color={target.versionPinned ? 'blue' : 'orange'}
                  icon={<IconAlertTriangle size={16} />}
                  title="Runs code inside your agent container"
                >
                  <Stack gap={6}>
                    {target.command && (
                      <Code block style={{ fontSize: 12 }}>
                        {target.command}
                      </Code>
                    )}
                    <Text fz={12}>
                      {target.versionPinned
                        ? 'This exact version is pinned, so it cannot change underneath you.'
                        : 'The registry published no fixed version, so a different release can be pulled at any session start.'}
                    </Text>
                  </Stack>
                </Alert>
              )}

              {target?.kind === 'remote' && target.url && (
                <Text fz={12} c="dimmed">
                  Endpoint <Code>{target.url}</Code>
                </Text>
              )}

              {(target?.inputs ?? []).length === 0 ? (
                <Text fz={13} c="dimmed">
                  No configuration needed. If this connector requires sign-in, you will be prompted to connect after
                  installing.
                </Text>
              ) : (
                <Stack gap="sm">
                  {(target?.inputs ?? []).map((input) => (
                    <Stack key={input.key} gap={4}>
                      <Group gap={6}>
                        {input.secret && (
                          <Badge size="xs" variant="light" color="gray" leftSection={<IconLock size={10} />}>
                            secret
                          </Badge>
                        )}
                        <Badge size="xs" variant="light" color="blue">
                          {input.kind}
                        </Badge>
                      </Group>
                      {/* A connector's inputs are the same kind of thing the manual
                          form takes — API keys, tokens, endpoints — so they get the
                          same affordance: type a value, or point at a secret this
                          project already holds instead of pasting it again. */}
                      <Group align="flex-end" gap={6} wrap="nowrap">
                        <ConfigItemValueField
                          label={input.key}
                          value={values[input.key] ?? ''}
                          onChange={(next) => setValues((prev) => ({ ...prev, [input.key]: next }))}
                          placeholder={input.placeholder ?? input.default ?? undefined}
                          configItemNames={configItemNames}
                        />
                      </Group>
                      {input.description && (
                        <Text fz={12} c="dimmed">
                          {input.description}
                        </Text>
                      )}
                    </Stack>
                  ))}
                </Stack>
              )}
            </>
          )}

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose}>
              Cancel
            </Button>
            <Button
              onClick={submit}
              loading={submitting}
              disabled={installable.length === 0 || missingRequired.length > 0}
            >
              Install
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
};
