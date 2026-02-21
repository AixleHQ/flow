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

import type { ConfigItem } from '../lib/types';

import { ConfigItemScopeBadge } from './ConfigItemScopeBadge';
import { ConfigItemTypeBadge } from './ConfigItemTypeBadge';

interface ConfigItemsTableProps {
  items: ConfigItem[];
  isProjectContext: boolean;
  onEdit: (item: ConfigItem) => void;
  onDelete: (item: ConfigItem) => void;
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
    fontFamily: '"JetBrains Mono", monospace',
    fontWeight: 500,
  },
  valueCell: {
    fontFamily: '"JetBrains Mono", monospace',
    color: 'text.secondaryAlt',
  },
  descriptionCell: {
    color: 'text.secondaryAlt',
    fontSize: 13,
    maxWidth: 300,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
} satisfies Record<string, SxProps | object>;

const ConfigItemsTable: FC<ConfigItemsTableProps> = ({ items, isProjectContext, onEdit, onDelete }) => {
  const canEdit = (item: ConfigItem): boolean => {
    // In project context, can only edit project-scoped items
    if (isProjectContext) {
      return item.scopeType === 'Project';
    }
    // In company context, can edit all items
    return true;
  };

  const canDelete = (item: ConfigItem): boolean => {
    return canEdit(item);
  };

  return (
    <TableContainer sx={styles.tableContainer}>
      <Table>
        <TableHead sx={styles.tableHead}>
          <TableRow>
            <TableCell sx={styles.tableHeadCell}>Name</TableCell>
            <TableCell sx={styles.tableHeadCell}>Type</TableCell>
            <TableCell sx={styles.tableHeadCell}>Value</TableCell>
            {isProjectContext && <TableCell sx={styles.tableHeadCell}>Scope</TableCell>}
            <TableCell sx={styles.tableHeadCell}>Description</TableCell>
            <TableCell sx={styles.tableHeadCell} align="right">
              Actions
            </TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {items.map((item) => (
            <TableRow key={`${item.scopeType}-${item.id}`} hover>
              <TableCell sx={{ ...styles.tableCell, ...styles.nameCell }}>{item.name}</TableCell>
              <TableCell sx={styles.tableCell}>
                <ConfigItemTypeBadge type={item.itemType} />
              </TableCell>
              <TableCell sx={{ ...styles.tableCell, ...styles.valueCell }}>{item.value}</TableCell>
              {isProjectContext && (
                <TableCell sx={styles.tableCell}>
                  <ConfigItemScopeBadge indicator={item.scopeIndicator} />
                </TableCell>
              )}
              <TableCell sx={styles.tableCell}>
                <Tooltip title={item.description || ''} placement="top">
                  <Typography sx={styles.descriptionCell}>{item.description || '—'}</Typography>
                </Tooltip>
              </TableCell>
              <TableCell sx={styles.tableCell} align="right">
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 0.5 }}>
                  {canEdit(item) && (
                    <Tooltip title="Edit">
                      <IconButton size="small" onClick={() => onEdit(item)}>
                        <EditIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canDelete(item) && (
                    <Tooltip title="Delete">
                      <IconButton size="small" onClick={() => onDelete(item)} sx={{ color: 'error.main' }}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {!canEdit(item) && !canDelete(item) && (
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

export { ConfigItemsTable };
