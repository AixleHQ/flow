import { ActionIcon, Alert, Anchor, Button, Group, Modal, Stack, Table, Text, Title, Tooltip } from '@mantine/core';
import { IconAlertTriangle, IconPencil, IconPlus, IconTrash } from '@tabler/icons-react';
import { type ReactNode, useState } from 'react';

import { formatDateTime } from 'shared/lib/formatDate';
import { companyProjectWorkflowRunPath } from 'shared/routes';

import {
  type AwsOidcConnection,
  type AwsOidcProps,
  type AwsOidcRole,
  type AwsOidcVerifyResult,
  confirmAwsOidcRoleDelete,
  connectAwsOidc,
  verifyAwsOidcRole,
} from './awsOidcActions';
import { AwsOidcRoleForm } from './AwsOidcRoleForm';
import { AwsOidcTrustPolicyPanel } from './AwsOidcTrustPolicyPanel';
import { CopyValue } from './CopyValue';

export type { AwsOidcProps } from './awsOidcActions';

type Verification =
  { pending: true } | { pending: false; result: AwsOidcVerifyResult } | { pending: false; error: string };

const Section = ({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) => (
  <Stack gap="xs">
    <Group justify="space-between">
      <Title order={5}>{title}</Title>
      {action}
    </Group>
    {children}
  </Stack>
);

const TrustValue = ({ label, value }: { label: string; value: string }) => (
  <Group gap="xs" wrap="nowrap">
    <Text size="sm" c="dimmed" w={90} style={{ flexShrink: 0 }}>
      {label}
    </Text>
    <Text size="sm" ff="monospace" style={{ wordBreak: 'break-all' }}>
      {value}
    </Text>
    <CopyValue label={label} value={value} />
  </Group>
);

const minutes = (seconds: number) => `${Math.round(seconds / 60)} min`;

function VerificationLine({ verification }: { verification: Verification }) {
  if (verification.pending) return null;
  if ('error' in verification)
    return (
      <Text size="xs" c="var(--app-danger-fg)">
        {verification.error}
      </Text>
    );
  const { result } = verification;
  return result.ok ? (
    <Text size="xs" c="var(--app-success-fg)" style={{ wordBreak: 'break-all' }}>
      Verified: AWS assumed {result.assumed_role_arn}
    </Text>
  ) : (
    <Text size="xs" c="var(--app-danger-fg)">
      {result.message}
    </Text>
  );
}

interface RolesProps {
  projectId: number;
  connection: AwsOidcConnection;
  canManage: boolean;
}

function RolesSection({ projectId, connection, canManage }: RolesProps) {
  // 'new' while adding, a role while editing it.
  const [editing, setEditing] = useState<AwsOidcRole | 'new' | null>(null);
  const [verifications, setVerifications] = useState<Record<number, Verification>>({});
  const { roles } = connection;

  const verify = async (role: AwsOidcRole) => {
    setVerifications((current) => ({ ...current, [role.id]: { pending: true } }));
    let verification: Verification;
    try {
      verification = { pending: false, result: await verifyAwsOidcRole(projectId, role.id) };
    } catch (e) {
      verification = { pending: false, error: e instanceof Error ? e.message : 'Flow could not verify the role' };
    }
    setVerifications((current) => ({ ...current, [role.id]: verification }));
  };

  return (
    <Section
      title="Roles"
      action={
        canManage &&
        editing === null && (
          <Button size="xs" variant="light" leftSection={<IconPlus size={14} />} onClick={() => setEditing('new')}>
            Add role
          </Button>
        )
      }
    >
      {roles.length === 0 ? (
        <Text size="sm" c="dimmed">
          No roles yet. Create a role in AWS that trusts the provider above, then add it here.
        </Text>
      ) : (
        <Table.ScrollContainer minWidth={560}>
          <Table verticalSpacing={6}>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Role ARN</Table.Th>
                <Table.Th>Region</Table.Th>
                <Table.Th>Session</Table.Th>
                {canManage && <Table.Th />}
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {roles.map((role) => {
                const verification = verifications[role.id];
                return [
                  <Table.Tr key={role.id}>
                    <Table.Td>
                      <Text size="sm" fw={500}>
                        {role.name}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Text size="xs" ff="monospace" style={{ wordBreak: 'break-all' }}>
                        {role.roleArn}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{role.region}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{minutes(role.sessionDurationSeconds)}</Text>
                    </Table.Td>
                    {canManage && (
                      <Table.Td>
                        <Group gap={4} justify="flex-end" wrap="nowrap">
                          <Button
                            size="compact-xs"
                            variant="light"
                            aria-label={`Verify ${role.name}`}
                            loading={verification?.pending}
                            onClick={() => void verify(role)}
                          >
                            Verify
                          </Button>
                          <Tooltip label="Edit">
                            <ActionIcon
                              aria-label={`Edit ${role.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={() => setEditing(role)}
                            >
                              <IconPencil size={16} />
                            </ActionIcon>
                          </Tooltip>
                          <Tooltip label="Delete">
                            <ActionIcon
                              aria-label={`Delete ${role.name}`}
                              variant="subtle"
                              size="sm"
                              color="red"
                              onClick={() => confirmAwsOidcRoleDelete(projectId, role)}
                            >
                              <IconTrash size={16} />
                            </ActionIcon>
                          </Tooltip>
                        </Group>
                      </Table.Td>
                    )}
                  </Table.Tr>,
                  verification && !verification.pending && (
                    <Table.Tr key={`${role.id}-verification`}>
                      <Table.Td colSpan={5} pt={0}>
                        <VerificationLine verification={verification} />
                      </Table.Td>
                    </Table.Tr>
                  ),
                ];
              })}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      )}
      {canManage && editing !== null && (
        <AwsOidcRoleForm
          key={editing === 'new' ? 'new' : editing.id}
          projectId={projectId}
          role={editing === 'new' ? null : editing}
          onDone={() => setEditing(null)}
        />
      )}
    </Section>
  );
}

function ActivitySection({ projectId, connection }: { projectId: number; connection: AwsOidcConnection }) {
  if (connection.activity.length === 0)
    return (
      <Section title="Activity">
        <Text size="sm" c="dimmed">
          No credentials issued yet.
        </Text>
      </Section>
    );

  return (
    <Section title="Activity">
      <Table.ScrollContainer minWidth={560}>
        <Table verticalSpacing={6}>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>When</Table.Th>
              <Table.Th>Role</Table.Th>
              <Table.Th>Workflow and step</Table.Th>
              <Table.Th>Run</Table.Th>
              <Table.Th>User</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {connection.activity.map((entry) => (
              <Table.Tr key={entry.id}>
                <Table.Td>
                  <Text size="sm">{formatDateTime(entry.createdAt)}</Text>
                </Table.Td>
                <Table.Td>
                  <Text size="sm">{entry.roleName}</Text>
                </Table.Td>
                <Table.Td>
                  <Text size="sm">
                    {entry.workflowName
                      ? [entry.workflowName, entry.stepName].filter(Boolean).join(' · ')
                      : entry.subject}
                  </Text>
                </Table.Td>
                <Table.Td>
                  {entry.workflowRunId ? (
                    <Anchor size="sm" href={companyProjectWorkflowRunPath(projectId, entry.workflowRunId)}>
                      #{entry.workflowRunId}
                    </Anchor>
                  ) : (
                    <Text size="sm" c="dimmed">
                      —
                    </Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Text size="sm">{entry.userName ?? '—'}</Text>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Section>
  );
}

interface Props {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  awsOidc: AwsOidcProps;
}

// The project's AWS OIDC integration (docs/design/aws-oidc-integration.md §8).
export function AwsOidcDialog({ opened, onClose, projectId, awsOidc }: Props) {
  const { connection } = awsOidc;
  const canManage = !!awsOidc.canManage;

  return (
    <Modal opened={opened && !!connection} onClose={onClose} title="AWS OIDC" size="xl">
      {connection && (
        <Stack gap="lg">
          {connection.status !== 'active' && (
            <Alert color="yellow" icon={<IconAlertTriangle size={16} />} title="Disconnected">
              <Stack gap="xs" align="flex-start">
                <Text size="sm">AWS refuses every token from this project, so steps that use these roles fail.</Text>
                {canManage && (
                  <Button size="xs" variant="light" onClick={() => connectAwsOidc(projectId)}>
                    Reconnect
                  </Button>
                )}
              </Stack>
            </Alert>
          )}

          <Section title="Trust">
            <Text size="sm" c="dimmed">
              In AWS IAM, add an OpenID Connect identity provider with this issuer URL as the provider URL and this
              audience. Each role below must trust that provider.
            </Text>
            <TrustValue label="Issuer URL" value={connection.issuerUrl} />
            <TrustValue label="Audience" value={connection.audience} />
          </Section>

          <RolesSection projectId={projectId} connection={connection} canManage={canManage} />

          <Section title="Trust policy">
            <AwsOidcTrustPolicyPanel connection={connection} />
          </Section>

          <ActivitySection projectId={projectId} connection={connection} />

          <Group justify="flex-end">
            <Button variant="default" onClick={onClose}>
              Close
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
