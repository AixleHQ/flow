import { Button, Group, Modal, Select, Stack, Table, Text } from '@mantine/core';
import { type ReactNode, useState } from 'react';

import type { HandoverChoice, ProjectHandover } from './projectHandover';

// Mount only while open: the preselected heirs are taken from props once.
interface Props {
  title: string;
  intro: ReactNode;
  confirmLabel: string;
  /** Who owns the projects, as the sentence names them: "They" or "You". */
  subject: 'They' | 'You';
  leavingUserId: number;
  handover: ProjectHandover;
  submitting?: boolean;
  onConfirm: (choices: HandoverChoice[]) => void;
  onClose: () => void;
}

export function ProjectHandoverModal({
  title,
  intro,
  confirmLabel,
  subject,
  leavingUserId,
  handover,
  submitting = false,
  onConfirm,
  onClose,
}: Props) {
  const projects = handover.projects.filter((p) => p.ownerId === leavingUserId);
  const candidates = handover.candidates.filter((c) => c.id !== leavingUserId);
  const options = candidates.map((c) => ({
    value: String(c.id),
    label: c.name ? `${c.name} (${c.email})` : c.email,
  }));
  const defaultHeir = handover.heirIds.find((id) => id !== leavingUserId && candidates.some((c) => c.id === id));

  const [heirs, setHeirs] = useState<Record<number, string | null>>(() =>
    Object.fromEntries(projects.map((p) => [p.id, defaultHeir != null ? String(defaultHeir) : null])),
  );

  const complete = projects.every((p) => heirs[p.id]);

  const confirm = () => onConfirm(projects.map((p) => ({ projectId: p.id, userId: Number(heirs[p.id]) })));

  return (
    <Modal opened onClose={onClose} title={<Text fw={600}>{title}</Text>} centered size="lg">
      <Stack gap="md">
        {intro}
        <Text size="sm">
          {subject} own{' '}
          {projects.length === 1
            ? '1 project here. Choose who takes it over first.'
            : `${projects.length} projects here. Choose who takes each one over first.`}
        </Text>
        <Table withRowBorders={false} verticalSpacing={6}>
          <Table.Tbody>
            {projects.map((project) => (
              <Table.Tr key={project.id}>
                <Table.Td>
                  <Text size="sm" fw={500}>
                    {project.name}
                  </Text>
                </Table.Td>
                <Table.Td w="60%">
                  <Select
                    aria-label={`New owner of ${project.name}`}
                    placeholder="Choose a member…"
                    data={options}
                    value={heirs[project.id]}
                    onChange={(v) => setHeirs((prev) => ({ ...prev, [project.id]: v }))}
                    searchable
                    nothingFoundMessage="No eligible members"
                    comboboxProps={{ withinPortal: true }}
                  />
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
        <Group justify="flex-end" gap="sm">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button color="red" disabled={!complete} loading={submitting} onClick={confirm}>
            {confirmLabel}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
