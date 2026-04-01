import DashboardIcon from '@mui/icons-material/Dashboard';
import { Box, Chip, Typography, type SxProps } from '@mui/material';
import { type FC, useEffect, useState, useCallback, useRef, useMemo } from 'react';

import { Routes } from 'shared/routes';

import type { MetaActivity } from './MetaActivityLog';

const styles = {
  root: { display: 'flex', flexDirection: 'column', height: '100%', overflow: 'hidden' },
  header: {
    px: 2,
    py: 1.5,
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    gap: 1,
  },
  title: { fontSize: 14, fontWeight: 600, color: 'text.primary' },
  content: { flex: 1, overflowY: 'auto', px: 2, py: 1 },
  empty: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    color: 'text.disabled',
    fontSize: 13,
  },
  column: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    py: 1,
    px: 1.5,
    mb: 0.5,
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'divider',
    '&:hover': { borderColor: 'primary.main' },
  },
  columnName: { fontSize: 13, fontWeight: 500, color: 'text.primary' },
  columnPurpose: { fontSize: 11, color: 'text.secondary', mt: 0.25 },
  binding: { fontSize: 11, color: 'primary.main', display: 'flex', alignItems: 'center', gap: 0.5 },
} satisfies Record<string, SxProps>;

interface BoardColumn {
  id: number;
  name: string;
  position: number;
  purpose: string | null;
  tasksCount: number;
  workflowBinding: {
    id: number;
    workflowId: number;
    workflowName: string;
    triggerMode: string;
    cooldownSeconds: number;
  } | null;
}

interface BoardData {
  boardId: number;
  name: string;
  presetOrigin: string | null;
  columnsCount: number;
  columns: BoardColumn[];
}

const BOARD_ACTIONS = new Set([
  'created_board_column',
  'updated_board_column',
  'deleted_board_column',
  'reordered_board_columns',
  'setup_board_from_preset',
  'created_column_binding',
  'updated_column_binding',
  'deleted_column_binding',
]);

interface BoardPreviewProps {
  projectId: number;
  activities?: MetaActivity[];
}

export const BoardPreview: FC<BoardPreviewProps> = ({ projectId, activities = [] }) => {
  const [board, setBoard] = useState<BoardData | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchBoard = useCallback(async () => {
    try {
      const response = await fetch(Routes.backend.apiV1CompanyProjectBoardPath(projectId), { credentials: 'include' });
      if (response.ok) {
        const data = await response.json();
        setBoard({
          boardId: data.id,
          name: data.name,
          presetOrigin: data.preset_origin,
          columnsCount: data.board_columns?.length || 0,
          columns: (data.board_columns || []).map(
            (col: {
              id: number;
              name: string;
              position: number;
              purpose: string | null;
              board_tasks_count?: number;
              column_workflow_binding?: {
                id: number;
                workflow_id: number;
                workflow_name?: string;
                trigger_mode: string;
                cooldown_seconds: number;
              } | null;
            }) => ({
              id: col.id,
              name: col.name,
              position: col.position,
              purpose: col.purpose,
              tasksCount: col.board_tasks_count || 0,
              workflowBinding: col.column_workflow_binding
                ? {
                    id: col.column_workflow_binding.id,
                    workflowId: col.column_workflow_binding.workflow_id,
                    workflowName: col.column_workflow_binding.workflow_name || 'Workflow',
                    triggerMode: col.column_workflow_binding.trigger_mode,
                    cooldownSeconds: col.column_workflow_binding.cooldown_seconds,
                  }
                : null,
            }),
          ),
        });
      }
    } catch {
      // Board may not exist yet
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  const boardActivityCount = useMemo(() => activities.filter((a) => BOARD_ACTIONS.has(a.action)).length, [activities]);
  const prevCountRef = useRef(boardActivityCount);

  useEffect(() => {
    fetchBoard();
    const interval = setInterval(fetchBoard, 10000);
    return () => clearInterval(interval);
  }, [fetchBoard]);

  useEffect(() => {
    if (boardActivityCount > prevCountRef.current) {
      prevCountRef.current = boardActivityCount;
      fetchBoard();
    }
  }, [boardActivityCount, fetchBoard]);

  if (loading) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.header}>
          <DashboardIcon sx={{ fontSize: 18 }} />
          <Typography sx={styles.title}>Board Preview</Typography>
        </Box>
        <Box sx={styles.empty}>Loading...</Box>
      </Box>
    );
  }

  if (!board || board.columns.length === 0) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.header}>
          <DashboardIcon sx={{ fontSize: 18 }} />
          <Typography sx={styles.title}>Board Preview</Typography>
        </Box>
        <Box sx={styles.empty}>No board configured</Box>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <DashboardIcon sx={{ fontSize: 18 }} />
        <Typography sx={styles.title}>{board.name}</Typography>
        {board.presetOrigin && <Chip label={board.presetOrigin} size="small" variant="outlined" />}
      </Box>
      <Box sx={styles.content}>
        {board.columns.map((col) => (
          <Box key={col.id} sx={styles.column}>
            <Box>
              <Typography sx={styles.columnName}>{col.name}</Typography>
              {col.purpose && <Typography sx={styles.columnPurpose}>{col.purpose}</Typography>}
            </Box>
            {col.workflowBinding ? (
              <Box sx={styles.binding}>
                {col.workflowBinding.triggerMode === 'auto' ? '\u26A1' : '\uD83D\uDC46'}
                {col.workflowBinding.workflowName}
              </Box>
            ) : (
              <Typography sx={{ fontSize: 11, color: 'text.disabled' }}>—</Typography>
            )}
          </Box>
        ))}
      </Box>
    </Box>
  );
};
