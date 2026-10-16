import { Head, usePage } from '@inertiajs/react';
import { Alert, Button, Loader, Paper, Select, Stack, Text, Title } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useEffect, useState } from 'react';

import { requestJson } from 'shared/resources/integrations/requestJson';
import { Logo, PageShell } from 'shared/ui';

interface ConnectableProject {
  id: number;
  name: string;
  companyName: string;
}

interface PageProps {
  projects: ConnectableProject[];
  preselectedProjectId: number | null;
  [key: string]: unknown;
}

interface Preview {
  workspace: { slug: string | null; name: string | null };
  bound_elsewhere: boolean;
}

interface Pairing {
  id: string;
  secret: string;
}

const CONNECT_PATH = '/integrations/bitbucket/connect';

// The Aixle Flow page in Bitbucket opens this with `#pairing=<id>.<secret>`.
// The fragment never reaches a server; it is read once and dropped from the URL.
const readPairing = (): Pairing | null => {
  const match = /pairing=([^.&]+)\.([^&]+)/.exec(window.location.hash);
  return match ? { id: match[1], secret: match[2] } : null;
};

const projectOptions = (projects: ConnectableProject[]) => {
  const severalCompanies = new Set(projects.map((p) => p.companyName)).size > 1;
  return projects.map((p) => ({
    value: String(p.id),
    label: severalCompanies ? `${p.name} · ${p.companyName}` : p.name,
  }));
};

const message = (e: unknown, fallback: string) => (e instanceof Error ? e.message : fallback);

export default function BitbucketConnect() {
  const { projects, preselectedProjectId } = usePage<PageProps>().props;
  const [pairing] = useState<Pairing | null>(readPairing);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [projectId, setProjectId] = useState<string | null>(() => {
    if (preselectedProjectId) return String(preselectedProjectId);
    return projects.length === 1 ? String(projects[0].id) : null;
  });

  useEffect(() => {
    if (!pairing) return;
    window.history.replaceState(null, '', CONNECT_PATH);
    requestJson(
      `${CONNECT_PATH}/preview`,
      { method: 'POST', body: JSON.stringify({ pairing_id: pairing.id, pairing_secret: pairing.secret }) },
      'This link is unknown or has expired',
    )
      .then((result) => setPreview(result as Preview))
      .catch((e: unknown) => setError(message(e, 'This link is unknown or has expired')));
  }, [pairing]);

  const confirm = async () => {
    if (!pairing || !projectId) return;
    setError(null);
    setSubmitting(true);
    try {
      const { redirect_url: redirectUrl } = (await requestJson(
        CONNECT_PATH,
        {
          method: 'POST',
          body: JSON.stringify({
            pairing_id: pairing.id,
            pairing_secret: pairing.secret,
            project_id: Number(projectId),
          }),
        },
        'Aixle could not connect the workspace',
      )) as { redirect_url: string };
      window.location.assign(redirectUrl);
    } catch (e) {
      setError(message(e, 'Aixle could not connect the workspace'));
      setSubmitting(false);
    }
  };

  const workspaceName = preview?.workspace.name || preview?.workspace.slug || 'this workspace';

  return (
    <PageShell variant="centered">
      <Head title="Connect Bitbucket" />
      <Paper p="xl" radius="md" w="100%" maw={460} withBorder>
        <Stack gap="md">
          <Logo />
          <Title order={3}>Connect Bitbucket</Title>

          {!pairing ? (
            <Text size="sm">
              This page opens from Bitbucket: a workspace administrator presses Connect in Workspace settings → Aixle
              Flow.
            </Text>
          ) : (
            <>
              {error && (
                <Alert color="red" icon={<IconAlertCircle size={16} />}>
                  {error}
                </Alert>
              )}
              {!preview && !error && <Loader size="sm" aria-label="Checking the link" />}
              {preview && (
                <>
                  <Text size="sm">
                    Connect the Bitbucket workspace <strong>{workspaceName}</strong>
                    {preview.workspace.slug ? ` (bitbucket.org/${preview.workspace.slug})` : ''} to an Aixle project.
                    Agents in that project can then clone its repositories and work on pull requests as the Aixle Flow
                    app.
                  </Text>
                  {preview.bound_elsewhere ? (
                    <Alert color="yellow">
                      This workspace is already connected to another Aixle company. A workspace administrator can
                      disconnect it from Workspace settings → Aixle Flow first.
                    </Alert>
                  ) : projects.length > 0 ? (
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
                  <Button
                    onClick={() => void confirm()}
                    loading={submitting}
                    disabled={!projectId || preview.bound_elsewhere}
                    fullWidth
                  >
                    Connect
                  </Button>
                  <Text size="xs" c="dimmed">
                    Only connect a workspace you started Connect for yourself. The link works once, for 10 minutes.
                  </Text>
                </>
              )}
            </>
          )}
        </Stack>
      </Paper>
    </PageShell>
  );
}
