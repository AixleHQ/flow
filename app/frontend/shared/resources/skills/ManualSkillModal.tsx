import { router } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Stack, Text, Textarea } from '@mantine/core';
import { IconInfoCircle } from '@tabler/icons-react';
import { useEffect, useState, type FC } from 'react';

interface ManualSkillModalProps {
  opened: boolean;
  onClose: () => void;
  /** Skills index path; the manual create action lives at `${basePath}/manual`. */
  basePath: string;
  /**
   * When present the modal edits that skill instead of creating one: the same file is
   * the same form, so there is no second editor to keep in sync.
   */
  skill?: { id: number; name: string; content: string | null } | null;
}

// A skill IS a SKILL.md, so the form is that file. Name and description are read
// from the frontmatter on the server rather than collected as separate fields: the
// Agent Skills spec requires a skill's name to equal its directory name, and a
// second input for the name is how that quietly breaks.
const STARTER = `---
name: my-skill
description: What this skill does, and when the agent should use it.
---

# My skill

Step-by-step instructions the agent should follow.
`;

export const ManualSkillModal: FC<ManualSkillModalProps> = ({ opened, onClose, basePath, skill = null }) => {
  const editing = !!skill;
  const [content, setContent] = useState(skill?.content ?? STARTER);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Reopening the modal on a different skill (or switching between edit and create)
  // has to reload the file being edited rather than keep the previous one.
  useEffect(() => {
    if (opened) {
      setContent(skill?.content ?? STARTER);
      setError(null);
    }
  }, [opened, skill?.id, skill?.content]);

  // A rejected SKILL.md must never cost the user their draft: the error is shown
  // beside the field and the textarea is left exactly as it was. Only success resets
  // and closes.
  const submit = () => {
    setSubmitting(true);
    setError(null);

    const options = {
      preserveScroll: true,
      preserveState: true,
      onSuccess: () => {
        setContent(editing ? content : STARTER);
        setError(null);
        onClose();
      },
      onError: (errors: Record<string, string>) =>
        setError(errors.content ?? `Could not ${editing ? 'update' : 'add'} the skill`),
      onFinish: () => setSubmitting(false),
    };

    if (editing) {
      router.patch(`${basePath}/${skill.id}`, { content }, options);
    } else {
      router.post(`${basePath}/manual`, { content }, options);
    }
  };

  return (
    <Modal opened={opened} onClose={onClose} title={editing ? `Edit ${skill.name}` : 'Add a skill by hand'} size="lg">
      <Stack gap="md">
        <Alert variant="light" color="blue" icon={<IconInfoCircle size={16} />}>
          <Text fz={13}>
            Paste a <code>SKILL.md</code>. The frontmatter needs a <code>name</code> (lowercase letters, numbers and
            single hyphens) and a <code>description</code> saying what the skill does and when to use it.
          </Text>
        </Alert>

        <Textarea
          label="SKILL.md"
          aria-label="SKILL.md content"
          value={content}
          onChange={(e) => setContent(e.currentTarget.value)}
          error={error}
          autosize
          minRows={14}
          maxRows={24}
          styles={{ input: { fontFamily: 'JetBrains Mono, monospace', fontSize: 12 } }}
        />

        {/* Skills written here never reach the skills.sh CLI, which reports every
            install upstream (source, skill name, and the path it landed at). */}
        <Text fz={11} c="dimmed">
          Stays on this project. It is written straight into the agent container — nothing about it is sent to
          skills.sh.{editing ? ' Sessions already running keep the previous version.' : ''}
        </Text>

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} loading={submitting} disabled={!content.trim()}>
            {editing ? 'Save changes' : 'Add skill'}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
