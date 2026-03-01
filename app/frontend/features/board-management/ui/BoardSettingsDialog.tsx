import AddIcon from '@mui/icons-material/Add';
import DeleteIcon from '@mui/icons-material/Delete';
import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import LinkIcon from '@mui/icons-material/Link';
import LinkOffIcon from '@mui/icons-material/LinkOff';
import {
  Box,
  Button,
  Chip,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  MenuItem,
  Stack,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import { type FC, useCallback, useEffect, useState } from 'react';

import type { BoardColumn } from 'entities/board-task';
import { useGetProjectWorkflowsQuery, type Workflow } from 'features/workflows';

import {
  useCreateColumnMutation,
  useUpdateColumnMutation,
  useDeleteColumnMutation,
  useReorderColumnsMutation,
  useCreateWorkflowBindingMutation,
  useUpdateWorkflowBindingMutation,
  useDeleteWorkflowBindingMutation,
} from '../api/boardApi';

interface BoardSettingsDialogProps {
  open: boolean;
  onClose: () => void;
  projectId: number;
  columns: BoardColumn[];
}

interface ColumnDraft {
  id: number;
  name: string;
  purpose: string;
  isNew?: boolean;
  dirty?: boolean;
  workflowId: number | null;
  triggerMode: string;
  workflowDirty?: boolean;
  workflowRemoved?: boolean;
}

export const BoardSettingsDialog: FC<BoardSettingsDialogProps> = ({ open, onClose, projectId, columns }) => {
  const [drafts, setDrafts] = useState<ColumnDraft[]>([]);
  const [deletedIds, setDeletedIds] = useState<number[]>([]);
  const [dragIdx, setDragIdx] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);

  const { data: workflows = [] } = useGetProjectWorkflowsQuery(projectId);

  const [createColumn] = useCreateColumnMutation();
  const [updateColumn] = useUpdateColumnMutation();
  const [deleteColumn] = useDeleteColumnMutation();
  const [reorderColumns] = useReorderColumnsMutation();
  const [createBinding] = useCreateWorkflowBindingMutation();
  const [updateBinding] = useUpdateWorkflowBindingMutation();
  const [deleteBinding] = useDeleteWorkflowBindingMutation();

  useEffect(() => {
    if (open) {
      setDrafts(
        columns.map((c) => ({
          id: c.id,
          name: c.name,
          purpose: c.purpose || '',
          workflowId: c.workflowBinding?.workflowId ?? null,
          triggerMode: c.workflowBinding?.triggerMode ?? 'manual',
        })),
      );
      setDeletedIds([]);
    }
  }, [open, columns]);

  const handleChange = (idx: number, field: keyof ColumnDraft, value: string | number | null) => {
    setDrafts((prev) =>
      prev.map((d, i) => {
        if (i !== idx) return d;
        const isWorkflowField = field === 'workflowId' || field === 'triggerMode';
        return {
          ...d,
          [field]: value,
          ...(isWorkflowField ? { workflowDirty: true, workflowRemoved: false } : { dirty: true }),
        };
      }),
    );
  };

  const handleRemoveWorkflow = (idx: number) => {
    setDrafts((prev) =>
      prev.map((d, i) =>
        i === idx ? { ...d, workflowId: null, triggerMode: 'manual', workflowDirty: true, workflowRemoved: true } : d,
      ),
    );
  };

  const handleAdd = () => {
    setDrafts((prev) => [
      ...prev,
      { id: -Date.now(), name: '', purpose: '', isNew: true, dirty: true, workflowId: null, triggerMode: 'manual' },
    ]);
  };

  const handleRemove = (idx: number) => {
    const draft = drafts[idx];
    if (!draft.isNew) setDeletedIds((prev) => [...prev, draft.id]);
    setDrafts((prev) => prev.filter((_, i) => i !== idx));
  };

  const handleDragStart = (idx: number) => setDragIdx(idx);
  const handleDragOver = (e: React.DragEvent, idx: number) => {
    e.preventDefault();
    if (dragIdx === null || dragIdx === idx) return;
    setDrafts((prev) => {
      const next = [...prev];
      const [moved] = next.splice(dragIdx, 1);
      next.splice(idx, 0, moved);
      return next;
    });
    setDragIdx(idx);
  };
  const handleDragEnd = () => setDragIdx(null);

  const handleSave = useCallback(async () => {
    setSaving(true);
    try {
      for (const id of deletedIds) {
        await deleteColumn({ projectId, id }).unwrap();
      }

      const createdIds: Record<number, number> = {};
      for (const draft of drafts) {
        if (draft.isNew && draft.name.trim()) {
          const result = await createColumn({
            projectId,
            boardColumn: { name: draft.name.trim(), purpose: draft.purpose.trim() || undefined },
          }).unwrap();
          createdIds[draft.id] = result.id;
        } else if (!draft.isNew && draft.dirty) {
          await updateColumn({
            projectId,
            id: draft.id,
            boardColumn: { name: draft.name.trim(), purpose: draft.purpose.trim() || undefined },
          }).unwrap();
        }
      }

      const orderedIds = drafts
        .filter((d) => d.name.trim())
        .map((d) => (d.isNew ? createdIds[d.id] : d.id))
        .filter(Boolean);

      if (orderedIds.length > 0) {
        await reorderColumns({ projectId, columnIds: orderedIds }).unwrap();
      }

      for (const draft of drafts) {
        if (!draft.workflowDirty) continue;
        const colId = draft.isNew ? createdIds[draft.id] : draft.id;
        if (!colId) continue;

        const originalCol = columns.find((c) => c.id === draft.id);
        const hadBinding = !!originalCol?.workflowBinding;

        if (draft.workflowRemoved && hadBinding) {
          await deleteBinding({ projectId, columnId: colId }).unwrap();
        } else if (draft.workflowId) {
          const method = hadBinding && !draft.isNew ? updateBinding : createBinding;
          await method({
            projectId,
            columnId: colId,
            workflowId: draft.workflowId,
            triggerMode: draft.triggerMode,
          }).unwrap();
        }
      }

      onClose();
    } finally {
      setSaving(false);
    }
  }, [
    drafts,
    deletedIds,
    projectId,
    columns,
    createColumn,
    updateColumn,
    deleteColumn,
    reorderColumns,
    createBinding,
    updateBinding,
    deleteBinding,
    onClose,
  ]);

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>Board Settings</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          Drag to reorder, rename, or remove columns. Assign workflows to auto-trigger when tasks enter a column.
        </Typography>

        <Stack spacing={1}>
          {drafts.map((draft, idx) => (
            <Box
              key={draft.id}
              draggable
              onDragStart={() => handleDragStart(idx)}
              onDragOver={(e) => handleDragOver(e, idx)}
              onDragEnd={handleDragEnd}
              sx={{
                display: 'flex',
                alignItems: 'center',
                gap: 1,
                p: 1,
                borderRadius: 1,
                backgroundColor: dragIdx === idx ? 'action.selected' : 'action.hover',
                cursor: 'grab',
                '&:active': { cursor: 'grabbing' },
              }}
            >
              <DragIndicatorIcon fontSize="small" sx={{ color: 'text.disabled', flexShrink: 0 }} />

              <TextField
                size="small"
                value={draft.name}
                onChange={(e) => handleChange(idx, 'name', e.target.value)}
                placeholder="Column name"
                sx={{ flex: 2 }}
                onClick={(e) => e.stopPropagation()}
              />

              <TextField
                size="small"
                value={draft.purpose}
                onChange={(e) => handleChange(idx, 'purpose', e.target.value)}
                placeholder="Purpose"
                sx={{ flex: 2 }}
                onClick={(e) => e.stopPropagation()}
              />

              <TextField
                select
                size="small"
                value={draft.workflowId ?? ''}
                onChange={(e) => handleChange(idx, 'workflowId', e.target.value ? Number(e.target.value) : null)}
                sx={{ flex: 2 }}
                onClick={(e) => e.stopPropagation()}
                label="Workflow"
              >
                <MenuItem value="">None</MenuItem>
                {(workflows as Workflow[]).map((w) => (
                  <MenuItem key={w.id} value={w.id}>
                    {w.name}
                  </MenuItem>
                ))}
              </TextField>

              {draft.workflowId && (
                <>
                  <Chip
                    size="small"
                    icon={<LinkIcon sx={{ fontSize: 14 }} />}
                    label={draft.triggerMode}
                    onClick={(e) => {
                      e.stopPropagation();
                      handleChange(idx, 'triggerMode', draft.triggerMode === 'auto' ? 'manual' : 'auto');
                    }}
                    color={draft.triggerMode === 'auto' ? 'primary' : 'default'}
                    sx={{ cursor: 'pointer' }}
                  />
                  <Tooltip title="Unlink workflow">
                    <IconButton size="small" onClick={() => handleRemoveWorkflow(idx)}>
                      <LinkOffIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                </>
              )}

              <Tooltip title="Remove column">
                <IconButton size="small" onClick={() => handleRemove(idx)} color="error">
                  <DeleteIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Box>
          ))}
        </Stack>

        <Button startIcon={<AddIcon />} onClick={handleAdd} sx={{ mt: 2 }} size="small">
          Add Column
        </Button>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={saving}>
          Cancel
        </Button>
        <Button variant="contained" onClick={handleSave} disabled={saving}>
          {saving ? 'Saving...' : 'Save'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
