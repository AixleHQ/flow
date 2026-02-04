import DeleteIcon from '@mui/icons-material/Delete';
import EditIcon from '@mui/icons-material/Edit';
import {
  Box,
  Chip,
  IconButton,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Tooltip,
  Paper,
} from '@mui/material';
import type { FC } from 'react';

import type { McpServer } from 'entities/mcp-server';

import { McpServerScopeBadge } from './McpServerScopeBadge';

interface McpServersTableProps {
  servers: McpServer[];
  isProjectContext: boolean;
  onEdit: (server: McpServer) => void;
  onDelete: (server: McpServer) => void;
}

export const McpServersTable: FC<McpServersTableProps> = ({ servers, isProjectContext, onEdit, onDelete }) => {
  return (
    <TableContainer component={Paper} variant="outlined">
      <Table>
        <TableHead>
          <TableRow>
            <TableCell>Name</TableCell>
            <TableCell>URL</TableCell>
            <TableCell>Transport</TableCell>
            <TableCell>Scope</TableCell>
            <TableCell>Status</TableCell>
            <TableCell align="right">Actions</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {servers.map((server) => {
            const canEdit = server.kind === 'custom' && (isProjectContext ? server.scopeType === 'Project' : true);

            return (
              <TableRow key={server.id} hover>
                <TableCell>
                  <Box>
                    <Box sx={{ fontWeight: 500 }}>{server.displayName}</Box>
                    <Box sx={{ fontSize: 12, color: 'text.secondary' }}>{server.name}</Box>
                  </Box>
                </TableCell>
                <TableCell>
                  <Box sx={{ maxWidth: 300, overflow: 'hidden', textOverflow: 'ellipsis' }}>{server.url}</Box>
                </TableCell>
                <TableCell>
                  <Chip label={server.transport.toUpperCase()} size="small" variant="outlined" />
                </TableCell>
                <TableCell>
                  <McpServerScopeBadge scopeIndicator={server.scopeIndicator} />
                </TableCell>
                <TableCell>
                  <Chip
                    label={server.enabled ? 'Enabled' : 'Disabled'}
                    color={server.enabled ? 'success' : 'default'}
                    size="small"
                  />
                </TableCell>
                <TableCell align="right">
                  {canEdit ? (
                    <>
                      <Tooltip title="Edit">
                        <IconButton size="small" onClick={() => onEdit(server)}>
                          <EditIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                      <Tooltip title="Delete">
                        <IconButton size="small" onClick={() => onDelete(server)} color="error">
                          <DeleteIcon fontSize="small" />
                        </IconButton>
                      </Tooltip>
                    </>
                  ) : (
                    <Box sx={{ color: 'text.disabled', fontSize: 12 }}>{server.internal ? 'System' : 'Read-only'}</Box>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </TableContainer>
  );
};
