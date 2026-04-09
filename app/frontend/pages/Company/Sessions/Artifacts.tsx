import { router, usePage } from '@inertiajs/react';
import { Alert, Badge, Box, Button, Checkbox, Group, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconAlertCircle, IconChevronLeft, IconDeviceFloppy, IconDownload, IconFile, IconX } from '@tabler/icons-react';
import { useCallback, useState } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

interface Session {
  id: number;
  agentType: string | null;
  state: string;
  artifactsReviewed: boolean | null;
  projectName: string | null;
}

interface Artifact {
  id: number;
  name: string;
  folder: string | null;
  status: string;
  fileSize: number | null;
  contentType: string | null;
  downloadUrl: string | null;
  createdAt: string;
}

interface Props {
  session: Session;
  artifacts: Artifact[];
  alreadyReviewed: boolean;
}

function formatFileSize(bytes: number | null): string {
  if (!bytes || bytes === 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const SessionArtifactsPage = () => {
  const { session, artifacts, alreadyReviewed } = usePage<{ props: Props }>().props as unknown as Props;

  const [selected, setSelected] = useState<Set<number>>(() => new Set(artifacts.map((a) => a.id)));
  const [submitting, setSubmitting] = useState(false);

  const allSelected = selected.size === artifacts.length && artifacts.length > 0;
  const noneSelected = selected.size === 0;

  const toggleOne = useCallback((id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const toggleAll = useCallback(() => {
    if (allSelected) {
      setSelected(new Set());
    } else {
      setSelected(new Set(artifacts.map((a) => a.id)));
    }
  }, [allSelected, artifacts]);

  const handleReview = useCallback(
    async (action: 'save' | 'dismiss_all') => {
      setSubmitting(true);

      const decisions: Record<string, string> = {};
      for (const a of artifacts) {
        if (action === 'dismiss_all') {
          decisions[String(a.id)] = 'dismiss';
        } else {
          decisions[String(a.id)] = selected.has(a.id) ? 'save' : 'dismiss';
        }
      }

      router.post(
        `/company/sessions/${session.id}/artifacts/review`,
        { decisions },
        {
          onFinish: () => setSubmitting(false),
        },
      );
    },
    [artifacts, selected, session.id],
  );

  return (
    <AuthLayout>
      <Box maw={900} mx="auto">
        <Group mb="lg">
          <Button
            variant="subtle"
            size="sm"
            leftSection={<IconChevronLeft size={16} />}
            onClick={() => router.visit(`/company/sessions/${session.id}`)}
          >
            Back to Session
          </Button>
          <Text size="xl" fw={600}>
            Session Artifacts
          </Text>
          <Text size="sm" c="dimmed" ff="monospace">
            #{session.id}
          </Text>
        </Group>

        {alreadyReviewed && (
          <Alert icon={<IconAlertCircle size={16} />} color="blue" mb="md">
            Outputs for this session have already been reviewed.
          </Alert>
        )}

        {artifacts.length === 0 ? (
          <Alert icon={<IconAlertCircle size={16} />} color="gray">
            No outputs collected from this session.
          </Alert>
        ) : (
          <Stack gap="md">
            <Table.ScrollContainer minWidth={600}>
              <Table striped highlightOnHover verticalSpacing={8}>
                <Table.Thead>
                  <Table.Tr>
                    {!alreadyReviewed && (
                      <Table.Th w={40}>
                        <Checkbox
                          checked={allSelected}
                          indeterminate={!allSelected && !noneSelected}
                          onChange={toggleAll}
                          aria-label="Select all"
                        />
                      </Table.Th>
                    )}
                    <Table.Th>File</Table.Th>
                    <Table.Th ta="right">Size</Table.Th>
                    <Table.Th>Type</Table.Th>
                    <Table.Th w={50} />
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {artifacts.map((a) => (
                    <Table.Tr key={a.id}>
                      {!alreadyReviewed && (
                        <Table.Td>
                          <Checkbox
                            checked={selected.has(a.id)}
                            onChange={() => toggleOne(a.id)}
                            aria-label={`Select ${a.name}`}
                          />
                        </Table.Td>
                      )}
                      <Table.Td>
                        <Group gap={8} wrap="nowrap">
                          <IconFile size={16} />
                          <Text size="sm" fw={500}>
                            {a.name}
                          </Text>
                          {a.status === 'active' && (
                            <Badge size="xs" color="green">
                              saved
                            </Badge>
                          )}
                        </Group>
                      </Table.Td>
                      <Table.Td ta="right">
                        <Text size="xs" ff="monospace" c="dimmed">
                          {formatFileSize(a.fileSize)}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="xs" c="dimmed">
                          {a.contentType ?? '—'}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        {a.downloadUrl && (
                          <Tooltip label="Download">
                            <a href={a.downloadUrl} target="_blank" rel="noreferrer">
                              <IconDownload size={16} />
                            </a>
                          </Tooltip>
                        )}
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>

            {!alreadyReviewed && (
              <Group justify="flex-end" gap="sm">
                <Button
                  variant="outline"
                  color="yellow"
                  leftSection={<IconX size={16} />}
                  onClick={() => handleReview('dismiss_all')}
                  loading={submitting}
                >
                  Dismiss all
                </Button>
                <Button
                  leftSection={<IconDeviceFloppy size={16} />}
                  onClick={() => handleReview('save')}
                  loading={submitting}
                  disabled={noneSelected}
                >
                  Save selected ({selected.size})
                </Button>
              </Group>
            )}
          </Stack>
        )}
      </Box>
    </AuthLayout>
  );
};

export default SessionArtifactsPage;
