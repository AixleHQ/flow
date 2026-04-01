import AccountTreeIcon from '@mui/icons-material/AccountTree';
import DashboardCustomizeIcon from '@mui/icons-material/DashboardCustomize';
import PersonIcon from '@mui/icons-material/Person';
import SmartToyIcon from '@mui/icons-material/SmartToy';
import ViewColumnIcon from '@mui/icons-material/ViewColumn';
import { Box, Chip, Typography, type SxProps } from '@mui/material';
import { type FC } from 'react';

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
  list: { flex: 1, overflowY: 'auto', px: 2, py: 1 },
  item: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 1,
    py: 0.75,
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': { borderBottom: 'none' },
  },
  itemIcon: { fontSize: 18, mt: 0.3, color: 'primary.main' },
  itemName: { fontSize: 13, fontWeight: 500, color: 'text.primary' },
  itemAction: { fontSize: 12, color: 'text.secondary' },
  itemTime: { fontSize: 11, color: 'text.disabled', mt: 0.25 },
  empty: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    color: 'text.disabled',
    fontSize: 13,
  },
} satisfies Record<string, SxProps>;

// Supports both snake_case (from DB/API) and camelCase (from WebSocket)
export interface MetaActivity {
  action: string;
  entity_type?: string;
  entityType?: string;
  entity_name?: string;
  entityName?: string;
  entity_id?: number;
  entityId?: number;
  timestamp: string;
}

const ENTITY_ICONS: Record<string, typeof PersonIcon> = {
  Workflow: AccountTreeIcon,
  Step: DashboardCustomizeIcon,
  SubStep: DashboardCustomizeIcon,
  Agent: PersonIcon,
  Tool: SmartToyIcon,
  Skill: SmartToyIcon,
  MCPServer: SmartToyIcon,
  BoardColumn: ViewColumnIcon,
  Board: ViewColumnIcon,
  ColumnWorkflowBinding: ViewColumnIcon,
};

const ACTION_LABELS: Record<string, string> = {
  created_workflow: 'Created workflow',
  deleted_workflow: 'Deleted workflow',
  created_step: 'Created step',
  created_sub_step: 'Created sub-step',
  updated_step: 'Updated step',
  deleted_step: 'Deleted step',
  reordered_steps: 'Reordered steps',
  created_agent: 'Created agent',
  created_tool: 'Created tool',
  created_skill: 'Created skill',
  created_mcp_server: 'Created MCP server',
  linked_tool: 'Linked tool',
  linked_skill: 'Linked skill',
  linked_mcp_server: 'Linked MCP server',
  finalized_workflow: 'Finalized workflow',
  created_board_column: 'Created column',
  updated_board_column: 'Updated column',
  deleted_board_column: 'Deleted column',
  reordered_board_columns: 'Reordered columns',
  created_column_binding: 'Created binding',
  updated_column_binding: 'Updated binding',
  deleted_column_binding: 'Deleted binding',
  setup_board_from_preset: 'Board from preset',
};

interface MetaActivityLogProps {
  activities: MetaActivity[];
}

export const MetaActivityLog: FC<MetaActivityLogProps> = ({ activities }) => {
  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Activity</Typography>
        {activities.length > 0 && <Chip label={activities.length} size="small" color="primary" />}
      </Box>
      <Box sx={styles.list}>
        {activities.length === 0 ? (
          <Box sx={styles.empty}>No builder activity yet</Box>
        ) : (
          [...activities].reverse().map((activity, idx) => {
            const entityType = activity.entity_type || activity.entityType || '';
            const entityName = activity.entity_name || activity.entityName || '';
            const IconComp = ENTITY_ICONS[entityType] || SmartToyIcon;
            return (
              <Box key={idx} sx={styles.item}>
                <IconComp sx={styles.itemIcon} />
                <Box sx={{ flex: 1 }}>
                  <Typography sx={styles.itemName}>{entityName}</Typography>
                  <Typography sx={styles.itemAction}>{ACTION_LABELS[activity.action] || activity.action}</Typography>
                  <Typography sx={styles.itemTime}>{new Date(activity.timestamp).toLocaleTimeString()}</Typography>
                </Box>
              </Box>
            );
          })
        )}
      </Box>
    </Box>
  );
};
