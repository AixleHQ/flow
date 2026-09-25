import { Head, Link, router, usePage } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  PasswordInput,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Table,
  Text,
  Textarea,
  TextInput,
  Title,
} from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import { useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { PageHeader } from 'shared/ui/PageHeader';

import { KindBadge } from './components/KindBadge';
import { templatePath, type TemplateDetail, type TemplateInput } from './types';

interface Pair {
  key: string;
  value: string;
}

interface PlanItem {
  section: string;
  key: string;
  name: string;
  action: 'create' | 'reuse' | 'copy' | 'conflict';
  existingId?: number;
  installName?: string;
}

interface Plan {
  target: 'new_project' | 'existing_project';
  projectName: string;
  digest: string;
  resolved: boolean;
  items: PlanItem[];
  boardAction: string;
  warnings: string[];
  checklist: { kind: string; ref: string }[];
}

interface Props {
  template: TemplateDetail;
  idempotencyKey: string;
  companyName: string;
  projects: { id: number; name: string }[];
  selection: { projectId: number | null; projectName: string | null; inputs: Pair[]; resolutions: Pair[] };
  plan: Plan | null;
  error: string | null;
}

const toRecord = (pairs: Pair[]) => Object.fromEntries(pairs.map((p) => [p.key, p.value]));

const ACTION_LABELS: Record<PlanItem['action'], string> = {
  create: 'Create',
  reuse: 'Use existing',
  copy: 'Install as copy',
  conflict: 'Conflict',
};

function InputField({
  input,
  value,
  onChange,
}: {
  input: TemplateInput;
  value: string;
  onChange: (v: string) => void;
}) {
  const common = { label: input.label, description: input.description, required: input.required };
  switch (input.type) {
    case 'select':
      return <Select {...common} data={input.options ?? []} value={value} onChange={(v) => onChange(v ?? '')} />;
    case 'boolean':
      return (
        <Switch
          label={input.label}
          description={input.description}
          checked={value === 'true'}
          onChange={(e) => onChange(String(e.currentTarget.checked))}
        />
      );
    case 'text':
      return (
        <Textarea {...common} autosize minRows={2} value={value} onChange={(e) => onChange(e.currentTarget.value)} />
      );
    default:
      return <TextInput {...common} value={value} onChange={(e) => onChange(e.currentTarget.value)} />;
  }
}

const InstallPage = () => {
  const { template, idempotencyKey, companyName, projects, selection, plan, error } = usePage()
    .props as unknown as Props;

  const [inputs, setInputs] = useState<Record<string, string>>(() => ({
    ...Object.fromEntries(template.inputs.map((i) => [i.key, i.default === undefined ? '' : String(i.default)])),
    ...toRecord(selection.inputs),
  }));
  const [secrets, setSecrets] = useState<Record<string, string>>({});
  const [projectName, setProjectName] = useState(selection.projectName ?? '');
  const [submitting, setSubmitting] = useState(false);

  const resolutions = toRecord(selection.resolutions);
  const intoExisting = selection.projectId !== null;
  const promptedSecrets = template.requires.secrets.filter((s) => s.promptAtInstall);

  // The plan depends on where the template goes and how conflicts are resolved,
  // so those changes re-plan on the server; inputs and secrets stay client-side.
  const replan = (changes: { projectId?: number | null; resolutions?: Record<string, string> }) => {
    const projectId = changes.projectId === undefined ? selection.projectId : changes.projectId;
    router.get(
      '/company/template_installs/new',
      {
        namespace: template.namespace,
        slug: template.slug,
        version: template.version,
        ...(projectId ? { project_id: projectId } : {}),
        ...(projectName ? { project_name: projectName } : {}),
        inputs,
        resolutions: changes.resolutions ?? resolutions,
      },
      { preserveState: true, preserveScroll: true, replace: true },
    );
  };

  const install = () => {
    if (!plan) return;
    setSubmitting(true);
    router.post(
      '/company/template_installs',
      {
        namespace: template.namespace,
        slug: template.slug,
        version: template.version,
        project_id: selection.projectId,
        project_name: projectName,
        inputs,
        secrets,
        resolutions,
        digest: plan.digest,
        idempotency_key: idempotencyKey,
      },
      { onFinish: () => setSubmitting(false) },
    );
  };

  const shown = plan?.items.filter((item) => item.section !== 'config_items') ?? [];

  return (
    <AuthLayout>
      <Head title={`Install ${template.name}`} />
      <Anchor component={Link} href={templatePath(template)} size="sm" c="var(--app-text-tertiary)">
        {template.name}
      </Anchor>
      <PageHeader
        title={`Install ${template.name}`}
        meta={<KindBadge kind={template.kind} />}
        subtitle={`Version ${template.version} · into ${companyName}`}
        mb={24}
      />

      <Stack gap="lg" maw={860}>
        <Card withBorder padding="lg" radius="md">
          <Stack gap="sm">
            <Title order={2} size="h4">
              Where it goes
            </Title>
            {template.kind === 'project' ? (
              <Text size="sm" c="var(--app-text-secondary)">
                A whole-project template always installs as a new project, owned by you.
              </Text>
            ) : (
              <SegmentedControl
                aria-label="Install target"
                value={intoExisting ? 'existing' : 'new'}
                onChange={(value) => replan({ projectId: value === 'new' ? null : (projects[0]?.id ?? null) })}
                data={[
                  { value: 'existing', label: 'An existing project', disabled: projects.length === 0 },
                  { value: 'new', label: 'A new project' },
                ]}
              />
            )}
            {intoExisting ? (
              <Select
                label="Project"
                data={projects.map((p) => ({ value: String(p.id), label: p.name }))}
                value={String(selection.projectId)}
                onChange={(value) => value && replan({ projectId: Number(value) })}
                searchable
              />
            ) : (
              <TextInput
                label="Project name"
                placeholder={plan?.projectName ?? template.name}
                value={projectName}
                onChange={(e) => setProjectName(e.currentTarget.value)}
              />
            )}
          </Stack>
        </Card>

        {(template.inputs.length > 0 || promptedSecrets.length > 0) && (
          <Card withBorder padding="lg" radius="md">
            <Stack gap="sm">
              <Title order={2} size="h4">
                Settings
              </Title>
              {template.inputs.map((input) => (
                <InputField
                  key={input.key}
                  input={input}
                  value={inputs[input.key] ?? ''}
                  onChange={(value) => setInputs((prev) => ({ ...prev, [input.key]: value }))}
                />
              ))}
              {promptedSecrets.map((secret) => (
                <PasswordInput
                  key={secret.name}
                  label={secret.name}
                  description={`${(secret.description ?? 'Secret').replace(/\.$/, '')} — optional now, you can add it from the checklist.`}
                  value={secrets[secret.name] ?? ''}
                  onChange={(e) => {
                    const value = e.currentTarget.value;
                    setSecrets((prev) => ({ ...prev, [secret.name]: value }));
                  }}
                  autoComplete="off"
                />
              ))}
            </Stack>
          </Card>
        )}

        {error && (
          <Alert color="red" icon={<IconAlertTriangle size={16} />} title="This template cannot be installed here">
            {error}
          </Alert>
        )}

        {plan && (
          <Card withBorder padding="lg" radius="md">
            <Stack gap="sm">
              <Title order={2} size="h4">
                What happens
              </Title>
              {plan.warnings.map((warning) => (
                <Alert key={warning} color="yellow" p="sm">
                  {warning}
                </Alert>
              ))}
              {template.runsThirdPartyImages && (
                <Alert color="yellow" icon={<IconAlertTriangle size={16} />} p="sm">
                  This template runs a third-party container image and third-party prompt text.
                </Alert>
              )}
              <Table verticalSpacing={6}>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Resource</Table.Th>
                    <Table.Th>Result</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {shown.map((item) => {
                    const ref = `${item.section}.${item.key}`;
                    const isConflict = item.action === 'conflict' || resolutions[ref] !== undefined;
                    return (
                      <Table.Tr key={ref}>
                        <Table.Td>
                          <Text size="sm">{item.name}</Text>
                          <Text size="xs" c="var(--app-text-tertiary)">
                            {item.section.replace(/_/g, ' ')}
                          </Text>
                        </Table.Td>
                        <Table.Td>
                          {isConflict ? (
                            <Stack gap={4}>
                              <Text size="xs" c="var(--app-warning-fg)">
                                A different {item.name} already exists in this project.
                              </Text>
                              <SegmentedControl
                                size="xs"
                                aria-label={`Resolve ${item.name}`}
                                value={resolutions[ref] ?? ''}
                                onChange={(value) => replan({ resolutions: { ...resolutions, [ref]: value } })}
                                data={[
                                  { value: 'copy', label: 'Install as copy' },
                                  { value: 'use_existing', label: 'Use existing' },
                                ]}
                              />
                              {item.action === 'copy' && item.installName && (
                                <Text size="xs" c="var(--app-text-tertiary)">
                                  Installs as {item.installName}
                                </Text>
                              )}
                            </Stack>
                          ) : (
                            <Badge variant="light" color={item.action === 'create' ? 'green' : 'gray'} tt="none">
                              {ACTION_LABELS[item.action]}
                              {item.installName && item.installName !== item.name ? ` as ${item.installName}` : ''}
                            </Badge>
                          )}
                        </Table.Td>
                      </Table.Tr>
                    );
                  })}
                </Table.Tbody>
              </Table>
              {plan.checklist.length > 0 && (
                <Text size="sm" c="var(--app-text-secondary)">
                  Afterwards, {plan.checklist.length} {plan.checklist.length === 1 ? 'thing is' : 'things are'} left on
                  the setup checklist. Every trigger starts inactive until you activate it there.
                </Text>
              )}
              <Group justify="flex-end">
                <Button onClick={install} loading={submitting} disabled={!plan.resolved}>
                  {plan.resolved ? 'Install' : 'Resolve the conflicts first'}
                </Button>
              </Group>
            </Stack>
          </Card>
        )}
      </Stack>
    </AuthLayout>
  );
};

export default InstallPage;
