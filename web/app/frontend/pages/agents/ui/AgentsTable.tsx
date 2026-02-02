import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import {
  Box,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Tooltip,
  Typography,
  type SxProps,
} from '@mui/material';
import type { FC } from 'react';

import type { Agent } from '../lib/types';

import { AgentScopeBadge } from './AgentScopeBadge';

interface AgentsTableProps {
  agents: Agent[];
  isProjectContext: boolean;
  onEdit: (agent: Agent) => void;
  onDelete: (agent: Agent) => void;
}

const styles = {
  tableContainer: {
    backgroundColor: 'background.surface',
    borderRadius: 1,
    border: '1px solid',
    borderColor: 'border.defaultAlt',
  },
  tableHead: {
    backgroundColor: 'background.base',
  },
  tableHeadCell: {
    color: 'text.secondaryAlt',
    fontWeight: 600,
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
  tableCell: {
    color: 'text.primaryAlt',
    fontSize: 14,
  },
  nameCell: {
    display: 'flex',
    alignItems: 'center',
    gap: 1.5,
  },
  iconBox: {
    fontSize: 24,
    width: 36,
    height: 36,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'background.base',
    borderRadius: 1,
  },
  agentName: {
    fontFamily: '"JetBrains Mono", monospace',
    fontWeight: 500,
    fontSize: 13,
    color: 'text.secondaryAlt',
  },
  agentTitle: {
    fontWeight: 500,
  },
  personaCell: {
    color: 'text.secondaryAlt',
    fontSize: 13,
    maxWidth: 400,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
} satisfies Record<string, SxProps | object>;

const AgentsTable: FC<AgentsTableProps> = ({ agents, isProjectContext, onEdit, onDelete }) => {
  const canEdit = (agent: Agent): boolean => {
    // In project context, can only edit project-scoped agents
    if (isProjectContext) {
      return agent.scopeType === 'Project';
    }
    // In company context, can edit all agents
    return true;
  };

  const canDelete = (agent: Agent): boolean => {
    return canEdit(agent);
  };

  return (
    <TableContainer sx={styles.tableContainer}>
      <Table>
        <TableHead sx={styles.tableHead}>
          <TableRow>
            <TableCell sx={styles.tableHeadCell}>Agent</TableCell>
            {isProjectContext && <TableCell sx={styles.tableHeadCell}>Scope</TableCell>}
            <TableCell sx={styles.tableHeadCell}>Persona</TableCell>
            <TableCell sx={styles.tableHeadCell} align="right">
              Actions
            </TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {agents.map((agent) => (
            <TableRow key={`${agent.scopeType}-${agent.id}`} hover>
              <TableCell sx={styles.tableCell}>
                <Box sx={styles.nameCell}>
                  <Box sx={styles.iconBox}>{agent.icon || '🤖'}</Box>
                  <Box>
                    <Typography sx={styles.agentTitle}>{agent.title}</Typography>
                    <Typography sx={styles.agentName}>{agent.name}</Typography>
                  </Box>
                </Box>
              </TableCell>
              {isProjectContext && (
                <TableCell sx={styles.tableCell}>
                  <AgentScopeBadge indicator={agent.scopeIndicator} />
                </TableCell>
              )}
              <TableCell sx={styles.tableCell}>
                <Tooltip title={agent.persona} placement="top">
                  <Typography sx={styles.personaCell}>{agent.persona}</Typography>
                </Tooltip>
              </TableCell>
              <TableCell sx={styles.tableCell} align="right">
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 0.5 }}>
                  {canEdit(agent) && (
                    <Tooltip title="Edit">
                      <IconButton size="small" onClick={() => onEdit(agent)}>
                        <EditIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canDelete(agent) && (
                    <Tooltip title="Delete">
                      <IconButton size="small" onClick={() => onDelete(agent)} sx={{ color: 'error.main' }}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {!canEdit(agent) && !canDelete(agent) && (
                    <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>Company-managed</Typography>
                  )}
                </Box>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
};

export { AgentsTable };
