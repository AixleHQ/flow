import { Button, Checkbox, Code, CopyButton, Group, MultiSelect, Select, Stack, Text, TextInput } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { useState } from 'react';

import type { AwsOidcConnection } from './awsOidcActions';
import { arnPartition, isAccountId, trustPolicyJson } from './awsOidcTrustPolicy';

const NEW_ROLE = 'new';

export function AwsOidcTrustPolicyPanel({ connection }: { connection: AwsOidcConnection }) {
  const { roles, workflows } = connection;
  const [roleKey, setRoleKey] = useState(() => (roles[0] ? String(roles[0].id) : NEW_ROLE));
  const [accountId, setAccountId] = useState('');
  const [workflowIds, setWorkflowIds] = useState<string[]>([]);
  const [allowDrafts, setAllowDrafts] = useState(false);

  const role = roles.find((r) => String(r.id) === roleKey) ?? null;
  const account = role ? (role.accountId ?? '') : accountId.trim();
  const policy = isAccountId(account)
    ? trustPolicyJson({
        accountId: account,
        issuerUrl: connection.issuerUrl,
        audience: connection.audience,
        verifySubject: connection.verifySubject,
        workflowIds: workflowIds.map(Number),
        allowDrafts,
        partition: role ? arnPartition(role.roleArn) : undefined,
      })
    : null;

  return (
    <Stack gap="sm">
      <Text size="sm" c="dimmed">
        Paste this as the role&apos;s trust policy in AWS. Steps of the workflows you pick can assume the role, and so
        can Verify.
      </Text>
      <Group grow align="flex-start">
        <Select
          label="Role"
          data={[
            ...roles.map((r) => ({ value: String(r.id), label: r.name })),
            { value: NEW_ROLE, label: 'A role not added yet' },
          ]}
          value={role ? roleKey : NEW_ROLE}
          onChange={(value) => setRoleKey(value ?? NEW_ROLE)}
          allowDeselect={false}
        />
        {!role && (
          <TextInput
            label="AWS account ID"
            placeholder="123456789012"
            value={accountId}
            onChange={(e) => setAccountId(e.currentTarget.value)}
            error={accountId.trim() && !isAccountId(accountId.trim()) ? 'Enter the 12-digit account ID' : null}
          />
        )}
      </Group>
      <MultiSelect
        label="Workflows"
        placeholder={workflowIds.length ? undefined : 'Pick the workflows whose steps use this role'}
        data={workflows.map((w) => ({ value: String(w.id), label: w.name }))}
        value={workflowIds}
        onChange={setWorkflowIds}
        searchable
        nothingFoundMessage="No workflows"
      />
      <Checkbox
        label="Allow draft test runs"
        description="Test runs of these workflows' unsaved drafts can assume the role too."
        checked={allowDrafts}
        onChange={(e) => setAllowDrafts(e.currentTarget.checked)}
      />
      {policy ? (
        <>
          <Code block aria-label="Trust policy">
            {policy}
          </Code>
          <Group justify="flex-end">
            <CopyButton value={policy}>
              {({ copied, copy }) => (
                <Button
                  size="xs"
                  variant="light"
                  leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                  onClick={copy}
                >
                  {copied ? 'Copied' : 'Copy policy'}
                </Button>
              )}
            </CopyButton>
          </Group>
        </>
      ) : (
        <Text size="sm" c="dimmed">
          Enter the AWS account ID of the role to see its trust policy.
        </Text>
      )}
    </Stack>
  );
}
