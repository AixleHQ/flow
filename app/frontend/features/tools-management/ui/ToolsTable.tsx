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
  Typography,
  type SxProps,
} from '@mui/material';
import type { FC } from 'react';

import type { Tool } from '../lib/types';

import { ToolScopeBadge } from './ToolScopeBadge';

interface ToolsTableProps {
  tools: Tool[];
  isProjectContext: boolean;
  onEdit: (tool: Tool) => void;
  onDelete: (tool: Tool) => void;
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
    flexDirection: 'column',
    gap: 0.5,
  },
  toolName: {
    fontFamily: '"JetBrains Mono", monospace',
    fontWeight: 500,
    fontSize: 13,
    color: 'text.secondaryAlt',
  },
  toolDisplayName: {
    fontWeight: 500,
  },
  descriptionCell: {
    color: 'text.secondaryAlt',
    fontSize: 13,
    maxWidth: 300,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  dockerImage: {
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: 12,
    color: 'text.secondaryAlt',
  },
} satisfies Record<string, SxProps | object>;

const ToolsTable: FC<ToolsTableProps> = ({ tools, isProjectContext, onEdit, onDelete }) => {
  const canEdit = (tool: Tool): boolean => {
    // Cannot edit internal tools
    if (tool.internal) return false;
    // In project context, can only edit project-scoped tools
    if (isProjectContext) {
      return tool.scopeIndicator === 'project' || tool.scopeIndicator === 'overrides_company';
    }
    // In company context, can edit company tools
    return tool.scopeIndicator === 'company';
  };

  const canDelete = (tool: Tool): boolean => {
    return canEdit(tool);
  };

  return (
    <TableContainer sx={styles.tableContainer}>
      <Table>
        <TableHead sx={styles.tableHead}>
          <TableRow>
            <TableCell sx={styles.tableHeadCell}>Tool</TableCell>
            <TableCell sx={styles.tableHeadCell}>Scope</TableCell>
            <TableCell sx={styles.tableHeadCell}>Docker Image</TableCell>
            <TableCell sx={styles.tableHeadCell}>Files</TableCell>
            <TableCell sx={styles.tableHeadCell} align="right">
              Actions
            </TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {tools.map((tool) => (
            <TableRow key={`${tool.scopeType}-${tool.id}`} hover>
              <TableCell sx={styles.tableCell}>
                <Box sx={styles.nameCell}>
                  <Typography sx={styles.toolDisplayName}>{tool.displayName}</Typography>
                  <Typography sx={styles.toolName}>{tool.name}</Typography>
                </Box>
              </TableCell>
              <TableCell sx={styles.tableCell}>
                <ToolScopeBadge indicator={tool.scopeIndicator} />
              </TableCell>
              <TableCell sx={styles.tableCell}>
                {tool.dockerImage ? (
                  <Typography sx={styles.dockerImage}>{tool.dockerImage}</Typography>
                ) : (
                  <Chip label="Built-in" size="small" variant="outlined" />
                )}
              </TableCell>
              <TableCell sx={styles.tableCell}>
                {tool.toolFiles.length > 0 ? (
                  <Chip label={`${tool.toolFiles.length} files`} size="small" variant="outlined" />
                ) : (
                  <Typography sx={{ color: 'text.disabled', fontSize: 13 }}>—</Typography>
                )}
              </TableCell>
              <TableCell sx={styles.tableCell} align="right">
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 0.5 }}>
                  {canEdit(tool) && (
                    <Tooltip title="Edit">
                      <IconButton size="small" onClick={() => onEdit(tool)}>
                        <EditIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canDelete(tool) && (
                    <Tooltip title="Delete">
                      <IconButton size="small" onClick={() => onDelete(tool)} sx={{ color: 'error.main' }}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {tool.internal && <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>System tool</Typography>}
                  {!tool.internal && !canEdit(tool) && (
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

export { ToolsTable };
