import { router } from '@inertiajs/react';
import { ActionIcon, Badge, Button, Checkbox, Group, Menu, Modal, Stack, Text, TextInput } from '@mantine/core';
import {
  IconAdjustmentsHorizontal,
  IconBookmark,
  IconBug,
  IconChevronDown,
  IconPlus,
  IconUser,
  IconX,
} from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import type BoardViewPreset from 'types/generated/BoardViewPreset';

import { apiMutate } from 'shared/lib/apiFetch';
import { apiV1ProjectViewPresetsPath, apiV1ProjectViewPresetPath } from 'shared/routes';

import { jsonHeaders, type BoardFilters } from './types';

export function ViewPresetMenu({
  projectId,
  viewPresets,
  currentUserId,
  filters,
  onApplyFilters,
}: {
  projectId: number;
  viewPresets: BoardViewPreset[];
  currentUserId: number;
  filters: BoardFilters;
  onApplyFilters: (filters: BoardFilters) => void;
}) {
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const [saveShared, setSaveShared] = useState(false);
  const [saving, setSaving] = useState(false);

  const hasActiveFilters = !!(
    filters.assigneeId ||
    filters.taskType ||
    filters.priority ||
    filters.tags.length > 0 ||
    filters.search
  );

  const builtInPresets = useMemo(
    () => [
      {
        id: 'my-work',
        name: 'My Work',
        icon: <IconUser size={14} />,
        apply: () =>
          onApplyFilters({
            assigneeId: String(currentUserId),
            taskType: null,
            priority: null,
            tags: [],
            search: '',
            showArchived: false,
          }),
      },
      {
        id: 'all-bugs',
        name: 'All Bugs',
        icon: <IconBug size={14} />,
        apply: () =>
          onApplyFilters({
            assigneeId: null,
            taskType: 'bug',
            priority: null,
            tags: [],
            search: '',
            showArchived: false,
          }),
      },
    ],
    [currentUserId, onApplyFilters],
  );

  const filtersToJson = (): Record<string, unknown> => {
    const result: Record<string, unknown> = {};
    if (filters.assigneeId) result.assignee_id = filters.assigneeId;
    if (filters.taskType) result.task_type = filters.taskType;
    if (filters.priority) result.priority = filters.priority;
    if (filters.tags.length > 0) result.tags = filters.tags;
    if (filters.search) result.search = filters.search;
    return result;
  };

  // Presets are saved with snake_case keys, and the server camelizes them on the way back.
  const applyViewPreset = (preset: BoardViewPreset) => {
    const f = preset.filters as Record<string, unknown>;
    const assigneeId = f.assigneeId ?? f.assignee_id;
    onApplyFilters({
      assigneeId: assigneeId ? String(assigneeId) : null,
      taskType: ((f.taskType ?? f.task_type) as string | undefined) ?? null,
      priority: (f.priority as string) ?? null,
      tags: (f.tags as string[]) ?? [],
      search: (f.search as string) ?? '',
      showArchived: false,
    });
  };

  const handleSave = async () => {
    if (!saveName.trim()) return;
    setSaving(true);
    const saved = await apiMutate(apiV1ProjectViewPresetsPath(projectId), {
      method: 'POST',
      headers: jsonHeaders,
      body: JSON.stringify({
        boardViewPreset: { name: saveName.trim(), shared: saveShared, filters: filtersToJson() },
      }),
    });
    if (saved) {
      router.reload({ only: ['view_presets'] });
      setSaveOpen(false);
      setSaveName('');
      setSaveShared(false);
    }
    setSaving(false);
  };

  const handleDelete = async (presetId: number) => {
    if (await apiMutate(apiV1ProjectViewPresetPath(projectId, presetId), { method: 'DELETE' })) {
      router.reload({ only: ['view_presets'] });
    }
  };

  return (
    <>
      <Menu shadow="md" width={220} position="bottom-start">
        <Menu.Target>
          <Button
            variant="default"
            size="xs"
            leftSection={<IconAdjustmentsHorizontal size={13} />}
            rightSection={<IconChevronDown size={11} />}
            styles={{ root: { fontWeight: 400 } }}
          >
            Presets
          </Button>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Label>Built-in</Menu.Label>
          {builtInPresets.map((bp) => (
            <Menu.Item key={bp.id} leftSection={bp.icon} onClick={bp.apply}>
              {bp.name}
            </Menu.Item>
          ))}

          {viewPresets.length > 0 && (
            <>
              <Menu.Divider />
              <Menu.Label>Saved</Menu.Label>
              {viewPresets.map((vp) => (
                <Menu.Item
                  key={vp.id}
                  onClick={() => applyViewPreset(vp)}
                  rightSection={
                    vp.userId === currentUserId ? (
                      <ActionIcon
                        size="xs"
                        variant="subtle"
                        color="red"
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDelete(vp.id);
                        }}
                      >
                        <IconX size={12} />
                      </ActionIcon>
                    ) : null
                  }
                  leftSection={<IconBookmark size={14} />}
                >
                  <Group gap={4}>
                    <Text size="sm">{vp.name}</Text>
                    {vp.shared && (
                      <Badge size="xs" variant="light" color="gray">
                        shared
                      </Badge>
                    )}
                  </Group>
                </Menu.Item>
              ))}
            </>
          )}

          {hasActiveFilters && (
            <>
              <Menu.Divider />
              <Menu.Item leftSection={<IconPlus size={14} />} onClick={() => setSaveOpen(true)}>
                Save current filters
              </Menu.Item>
            </>
          )}
        </Menu.Dropdown>
      </Menu>

      <Modal opened={saveOpen} onClose={() => setSaveOpen(false)} title="Save Filter Preset" centered size="sm">
        <Stack gap="md">
          <TextInput
            label="Preset name"
            placeholder="e.g. Sprint 5 tasks"
            value={saveName}
            onChange={(e) => setSaveName(e.currentTarget.value)}
            autoFocus
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSave();
            }}
          />
          <Checkbox
            label="Share with team members"
            checked={saveShared}
            onChange={(e) => setSaveShared(e.currentTarget.checked)}
          />
          <Group justify="flex-end">
            <Button variant="outline" onClick={() => setSaveOpen(false)}>
              Cancel
            </Button>
            <Button onClick={handleSave} loading={saving} disabled={!saveName.trim()}>
              Save
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
