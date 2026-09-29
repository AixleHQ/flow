import { router } from '@inertiajs/react';
import { Badge, Box, Button, Card, Group, SimpleGrid, Stack, Text, ThemeIcon } from '@mantine/core';
import { IconColumns, IconLayoutKanban, IconSettings } from '@tabler/icons-react';
import { useState } from 'react';

import type BoardPreset from 'types/generated/BoardPreset';

import { apiMutate } from 'shared/lib/apiFetch';
import { apiV1ProjectBoardPath } from 'shared/routes';

import { jsonHeaders } from './types';

// --- Board Preset Picker (empty board state) ---

const PRESET_ICONS: Record<string, React.ReactNode> = {
  simple_kanban: <IconLayoutKanban size={32} />,
  dev_team: <IconColumns size={32} />,
  full_sdlc: <IconSettings size={32} />,
};

export function BoardPresetPicker({ projectId, presets }: { projectId: number; presets: BoardPreset[] }) {
  const [creating, setCreating] = useState<string | null>(null);

  const handleCreate = async (presetKey: string) => {
    setCreating(presetKey);
    const created = await apiMutate(apiV1ProjectBoardPath(projectId), {
      method: 'POST',
      headers: jsonHeaders,
      body: JSON.stringify({ board: { preset: presetKey, name: 'Project Board' } }),
    });
    if (created) router.reload();
    else setCreating(null);
  };

  return (
    <Box py={60} maw={700} mx="auto">
      <Stack align="center" mb="xl">
        <ThemeIcon size={64} radius="xl" variant="light" color="brand">
          <IconLayoutKanban size={32} />
        </ThemeIcon>
        <Text size="xl" fw={700}>
          Create your task board
        </Text>
        <Text c="dimmed" size="sm" ta="center" maw={400}>
          Pick a template that fits your workflow. You can customize columns later.
        </Text>
      </Stack>

      <SimpleGrid cols={{ base: 1, sm: presets.length >= 3 ? 3 : presets.length }} spacing="md">
        {presets.map((preset) => (
          <Card
            key={preset.key}
            withBorder
            padding="lg"
            radius="md"
            style={{ cursor: creating ? 'not-allowed' : 'pointer', transition: 'transform 0.15s, box-shadow 0.15s' }}
            onMouseEnter={(e) => {
              if (!creating) {
                (e.currentTarget as HTMLElement).style.transform = 'translateY(-2px)';
                (e.currentTarget as HTMLElement).style.boxShadow = 'var(--mantine-shadow-md)';
              }
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.transform = '';
              (e.currentTarget as HTMLElement).style.boxShadow = '';
            }}
            onClick={() => !creating && handleCreate(preset.key)}
          >
            <Stack align="center" gap="sm">
              <ThemeIcon size={48} radius="md" variant="light" color="brand">
                {PRESET_ICONS[preset.key] ?? <IconLayoutKanban size={28} />}
              </ThemeIcon>
              <Text fw={600} ta="center">
                {preset.displayName}
              </Text>
              <Group gap={4} wrap="wrap" justify="center">
                {preset.columns.map((col) => (
                  <Badge key={col} size="xs" variant="outline" color="gray">
                    {col}
                  </Badge>
                ))}
              </Group>
              <Button
                fullWidth
                variant="light"
                loading={creating === preset.key}
                disabled={!!creating && creating !== preset.key}
              >
                Use this template
              </Button>
            </Stack>
          </Card>
        ))}
      </SimpleGrid>
    </Box>
  );
}
