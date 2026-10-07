import { Head, router, usePage } from '@inertiajs/react';
import { Alert, Button, Paper, Select, Stack, Text, TextInput, Title } from '@mantine/core';
import { IconAlertCircle, IconCircleCheck } from '@tabler/icons-react';
import { type FormEvent, useState } from 'react';

import { Logo, PageShell, type SharedProps } from 'shared/ui';

interface ConnectableProject {
  id: number;
  name: string;
  companyName: string;
}

interface PageProps {
  projects: ConnectableProject[];
  flash?: SharedProps['flash'];
  [key: string]: unknown;
}

const CONNECT_PATH = '/integrations/youtrack/connect';

const projectOptions = (projects: ConnectableProject[]) => {
  const severalCompanies = new Set(projects.map((p) => p.companyName)).size > 1;
  return projects.map((p) => ({
    value: String(p.id),
    label: severalCompanies ? `${p.name} · ${p.companyName}` : p.name,
  }));
};

export default function YoutrackConnect() {
  const { projects, flash = {} } = usePage<PageProps>().props;
  const [code, setCode] = useState('');
  const [projectId, setProjectId] = useState<string | null>(projects.length === 1 ? String(projects[0].id) : null);
  const [submitting, setSubmitting] = useState(false);
  const notice = typeof flash.notice === 'string' ? flash.notice : null;
  const alert = typeof flash.alert === 'string' ? flash.alert : null;

  const approve = (event: FormEvent) => {
    event.preventDefault();
    if (!code.trim() || !projectId) return;
    setSubmitting(true);
    router.post(
      CONNECT_PATH,
      { code: code.trim(), project_id: Number(projectId) },
      { onFinish: () => setSubmitting(false) },
    );
  };

  return (
    <PageShell variant="centered">
      <Head title="Connect YouTrack" />
      <Paper p="xl" radius="md" w="100%" maw={440} withBorder>
        <Stack gap="md">
          <Logo />
          <Title order={3}>Connect YouTrack</Title>

          {notice ? (
            <>
              <Alert color="green" icon={<IconCircleCheck size={16} />}>
                {notice}
              </Alert>
              <Text size="sm">
                Return to the YouTrack tab: the Aixle Flow page there finishes connecting by itself. You can close this
                window.
              </Text>
            </>
          ) : (
            <form onSubmit={approve}>
              <Stack gap="md">
                <Text size="sm" c="dimmed">
                  Enter the code the Aixle Flow app shows in YouTrack, and choose the Aixle project it connects to.
                </Text>
                {alert && (
                  <Alert color="red" icon={<IconAlertCircle size={16} />}>
                    {alert}
                  </Alert>
                )}
                <TextInput
                  label="Code"
                  placeholder="ABCD-2345"
                  value={code}
                  onChange={(event) => setCode(event.currentTarget.value)}
                  autoComplete="off"
                  autoCapitalize="characters"
                  spellCheck={false}
                  autoFocus
                />
                {projects.length > 0 ? (
                  <Select
                    label="Aixle project"
                    placeholder="Choose a project"
                    data={projectOptions(projects)}
                    value={projectId}
                    onChange={setProjectId}
                    searchable
                  />
                ) : (
                  <Alert color="yellow">
                    You have no project you can connect integrations in. Ask an administrator of your company.
                  </Alert>
                )}
                <Button type="submit" loading={submitting} disabled={!code.trim() || !projectId} fullWidth>
                  Approve
                </Button>
                <Text size="xs" c="dimmed">
                  Only a YouTrack administrator who started Connect in YouTrack (Administration → Integrations › Aixle
                  Flow) has a code. A code is valid for 15 minutes.
                </Text>
              </Stack>
            </form>
          )}
        </Stack>
      </Paper>
    </PageShell>
  );
}
