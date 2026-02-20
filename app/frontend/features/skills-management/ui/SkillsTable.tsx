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

import type { Skill } from '../lib/types';

import { SkillKindBadge } from './SkillKindBadge';
import { SkillScopeBadge } from './SkillScopeBadge';

interface SkillsTableProps {
  skills: Skill[];
  isProjectContext: boolean;
  onEdit: (skill: Skill) => void;
  onDelete: (skill: Skill) => void;
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
    fontSize: 13,
  },
  titleCell: {
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
} satisfies Record<string, SxProps | object>;

const SkillsTable: FC<SkillsTableProps> = ({ skills, isProjectContext, onEdit, onDelete }) => {
  const canEdit = (skill: Skill): boolean => {
    // Internal skills are read-only
    if (skill.internal) return false;
    // In project context, can only edit project-scoped skills
    if (isProjectContext) return skill.scopeType === 'Project';
    // In company context, can edit all custom skills
    return true;
  };

  const canDelete = (skill: Skill): boolean => {
    return canEdit(skill);
  };

  return (
    <TableContainer sx={styles.tableContainer}>
      <Table>
        <TableHead sx={styles.tableHead}>
          <TableRow>
            <TableCell sx={styles.tableHeadCell}>Name</TableCell>
            <TableCell sx={styles.tableHeadCell}>Title</TableCell>
            <TableCell sx={styles.tableHeadCell}>Kind</TableCell>
            {isProjectContext && <TableCell sx={styles.tableHeadCell}>Scope</TableCell>}
            <TableCell sx={styles.tableHeadCell}>Description</TableCell>
            <TableCell sx={styles.tableHeadCell} align="right">
              Actions
            </TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {skills.map((skill) => (
            <TableRow key={`${skill.scopeType}-${skill.id}`} hover>
              <TableCell sx={styles.tableCell}>
                <Typography sx={styles.nameCell}>{skill.name}</Typography>
              </TableCell>
              <TableCell sx={styles.tableCell}>
                <Typography sx={styles.titleCell}>{skill.title || '—'}</Typography>
              </TableCell>
              <TableCell sx={styles.tableCell}>
                <SkillKindBadge kind={skill.kind} />
              </TableCell>
              {isProjectContext && (
                <TableCell sx={styles.tableCell}>
                  <SkillScopeBadge indicator={skill.scopeIndicator} />
                </TableCell>
              )}
              <TableCell sx={styles.tableCell}>
                <Tooltip title={skill.description || ''} placement="top">
                  <Typography sx={styles.descriptionCell}>{skill.description || '—'}</Typography>
                </Tooltip>
              </TableCell>
              <TableCell sx={styles.tableCell} align="right">
                <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 0.5 }}>
                  {canEdit(skill) && (
                    <Tooltip title="Edit">
                      <IconButton size="small" onClick={() => onEdit(skill)}>
                        <EditIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {canDelete(skill) && (
                    <Tooltip title="Delete">
                      <IconButton size="small" onClick={() => onDelete(skill)} sx={{ color: 'error.main' }}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  )}
                  {!canEdit(skill) && !canDelete(skill) && (
                    <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>
                      {skill.internal ? 'System' : 'Company-managed'}
                    </Typography>
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

export { SkillsTable };
