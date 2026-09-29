import { DndContext, PointerSensor, closestCorners, useSensor, useSensors, type DragEndEvent } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Stack, Text } from '@mantine/core';
import { IconPlus } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { apiMutate, apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { apiV1ProjectColumnPath, apiV1ProjectColumnsPath, reorderApiV1ProjectColumnsPath } from 'shared/routes';

import { SortableColumnRow } from './SortableColumnRow';
import { jsonHeaders, type ColState, type Column } from './types';

// --- Board Settings Dialog (with drag-to-reorder columns) ---

export function BoardSettingsDialog({
  opened,
  onClose,
  projectId,
  columns: initialColumns,
}: {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  columns: Column[];
}) {
  const [cols, setCols] = useState<ColState[]>([]);
  const [saving, setSaving] = useState(false);
  const [deletedIds, setDeletedIds] = useState<number[]>([]);

  useEffect(() => {
    if (opened) {
      setCols(
        initialColumns.map((c) => ({
          id: c.id,
          name: c.name,
          purpose: c.purpose ?? '',
          workflowId: c.workflowBinding?.workflowId ? String(c.workflowBinding.workflowId) : null,
          triggerMode: c.workflowBinding?.triggerMode ?? 'auto',
          bindingId: c.workflowBinding?.id ?? null,
          bindingChanged: false,
        })),
      );
      setDeletedIds([]);
    }
  }, [opened, initialColumns]);

  const addColumn = () =>
    setCols((prev) => [
      ...prev,
      {
        id: null,
        name: '',
        purpose: '',
        workflowId: null,
        triggerMode: 'auto',
        bindingId: null,
        bindingChanged: false,
      },
    ]);

  const removeColumn = (idx: number) => {
    const col = cols[idx];
    if (col.id) setDeletedIds((prev) => [...prev, col.id!]);
    setCols((prev) => prev.filter((_, i) => i !== idx));
  };

  const updateCol = (idx: number, field: keyof ColState, value: string | number | null) => {
    setCols((prev) =>
      prev.map((c, i) => {
        if (i !== idx) return c;
        const updated = { ...c, [field]: value };
        if (['workflowId', 'triggerMode'].includes(field)) updated.bindingChanged = true;
        return updated;
      }),
    );
  };

  const settingsSensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  const sortableIds = useMemo(() => cols.map((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`)), [cols]);

  const handleColumnDragEnd = useCallback((event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    setCols((prev) => {
      const oldIndex = prev.findIndex((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`) === active.id);
      const newIndex = prev.findIndex((c, i) => (c.id ? `col-${c.id}` : `col-new-${i}`) === over.id);
      if (oldIndex === -1 || newIndex === -1) return prev;

      const next = [...prev];
      const [moved] = next.splice(oldIndex, 1);
      next.splice(newIndex, 0, moved);
      return next;
    });
  }, []);

  const handleSave = async () => {
    setSaving(true);

    for (const id of deletedIds) {
      await apiMutate(apiV1ProjectColumnPath(projectId, id), { method: 'DELETE' });
    }

    const createdIdMap = new Map<number, number>();

    for (let i = 0; i < cols.length; i++) {
      const col = cols[i];
      if (col.id) {
        const orig = initialColumns.find((c) => c.id === col.id);
        if (orig && (orig.name !== col.name || (orig.purpose ?? '') !== col.purpose)) {
          await apiMutate(apiV1ProjectColumnPath(projectId, col.id), {
            method: 'PATCH',
            headers: jsonHeaders,
            body: JSON.stringify({ boardColumn: { name: col.name, purpose: col.purpose || null } }),
          });
        }
      } else if (col.name.trim()) {
        try {
          const created = await apiRequest<{ id: number }>(apiV1ProjectColumnsPath(projectId), {
            method: 'POST',
            headers: jsonHeaders,
            body: JSON.stringify({ boardColumn: { name: col.name, purpose: col.purpose || null } }),
          });
          createdIdMap.set(i, created.id);
        } catch (error) {
          notifyApiFailure(error, `Column "${col.name}" was not created`);
        }
      }
    }

    const allIds = cols.map((c, i) => c.id ?? createdIdMap.get(i)).filter((id): id is number => id != null);
    if (allIds.length > 0) {
      await apiMutate(reorderApiV1ProjectColumnsPath(projectId), {
        method: 'PATCH',
        headers: jsonHeaders,
        body: JSON.stringify({ columnIds: allIds }),
      });
    }

    setSaving(false);
    onClose();
    router.reload({ only: ['columns', 'tasks', 'workflows'] });
  };

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title="Board Settings"
      centered
      size="xl"
      styles={{
        content: { display: 'flex', flexDirection: 'column', maxHeight: '80vh' },
        body: { flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' },
      }}
    >
      <Text size="sm" c="dimmed" mb="md">
        Drag to reorder, rename, or remove columns. Assign workflows to auto-trigger when tasks enter a column.
      </Text>
      <DndContext sensors={settingsSensors} collisionDetection={closestCorners} onDragEnd={handleColumnDragEnd}>
        <SortableContext items={sortableIds} strategy={verticalListSortingStrategy}>
          <Box style={{ flex: 1, minHeight: 0, overflowY: 'auto', paddingRight: 4 }}>
            <Stack gap="md">
              {cols.map((col, idx) => (
                <SortableColumnRow
                  key={col.id ? `col-${col.id}` : `col-new-${idx}`}
                  col={col}
                  idx={idx}
                  updateCol={updateCol}
                  removeColumn={removeColumn}
                />
              ))}
            </Stack>
          </Box>
        </SortableContext>
      </DndContext>
      <Group mt="md" justify="space-between" style={{ flexShrink: 0 }}>
        <Button variant="outline" size="sm" leftSection={<IconPlus size={14} />} onClick={addColumn}>
          Add Column
        </Button>
        <Group gap="sm">
          <Button variant="outline" size="sm" onClick={onClose}>
            Cancel
          </Button>
          <Button size="sm" loading={saving} onClick={handleSave}>
            Save
          </Button>
        </Group>
      </Group>
    </Modal>
  );
}
