import ClearIcon from '@mui/icons-material/Clear';
import SearchIcon from '@mui/icons-material/Search';
import {
  Autocomplete,
  Box,
  Button,
  Chip,
  FormControl,
  InputAdornment,
  InputLabel,
  MenuItem,
  Select,
  TextField,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';

import { COMMENT_TAG_SUGGESTIONS } from 'entities/board-task';

import { useGetViewPresetsQuery, useCreateViewPresetMutation, useDeleteViewPresetMutation } from '../api/boardApi';

import { PresetSelector } from './PresetSelector';

export interface BoardFilters {
  assigneeId?: string;
  taskType?: string;
  priority?: string;
  tags?: string[];
  search?: string;
}

interface BoardFilterBarProps {
  filters: BoardFilters;
  onChange: (filters: BoardFilters) => void;
  members?: Array<{ id: number; name: string }>;
  projectId: number;
  currentUserId?: number;
}

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    gap: 1,
    flexWrap: 'wrap',
    mb: 1.5,
  },
  select: {
    minWidth: 130,
  },
  search: {
    minWidth: 180,
  },
  tags: {
    minWidth: 200,
  },
} satisfies Record<string, SxProps<Theme>>;

const TASK_TYPES = [
  { value: '', label: 'All types' },
  { value: 'epic', label: 'Epic' },
  { value: 'story', label: 'Story' },
  { value: 'bug', label: 'Bug' },
  { value: 'not_specified', label: 'Not specified' },
];

const PRIORITIES = [
  { value: '', label: 'All priorities' },
  { value: 'critical', label: 'Critical' },
  { value: 'high', label: 'High' },
  { value: 'medium', label: 'Medium' },
  { value: 'low', label: 'Low' },
];

const hasActiveFilters = (f: BoardFilters) =>
  Boolean(f.assigneeId || f.taskType || f.priority || f.tags?.length || f.search);

export const BoardFilterBar = ({ filters, onChange, members = [], projectId, currentUserId }: BoardFilterBarProps) => {
  const { data: savedPresets = [] } = useGetViewPresetsQuery(projectId);
  const [createPreset] = useCreateViewPresetMutation();
  const [deletePreset] = useDeleteViewPresetMutation();

  const builtInPresets = [
    {
      id: 'my-work',
      name: 'My Work',
      filters: { assigneeId: currentUserId ? String(currentUserId) : '' },
      isBuiltIn: true,
    },
    { id: 'all-bugs', name: 'All Bugs', filters: { taskType: 'bug' }, isBuiltIn: true },
  ];

  const allPresets = [...builtInPresets, ...savedPresets.map((p) => ({ ...p, isBuiltIn: false }))];

  const active = hasActiveFilters(filters);

  return (
    <Box sx={styles.root}>
      <FormControl size="small" sx={styles.select}>
        <InputLabel>Assignee</InputLabel>
        <Select
          value={filters.assigneeId || ''}
          label="Assignee"
          onChange={(e) => onChange({ ...filters, assigneeId: e.target.value || undefined })}
        >
          <MenuItem value="">All</MenuItem>
          {members.map((m) => (
            <MenuItem key={m.id} value={String(m.id)}>
              {m.name}
            </MenuItem>
          ))}
        </Select>
      </FormControl>

      <FormControl size="small" sx={styles.select}>
        <InputLabel>Type</InputLabel>
        <Select
          value={filters.taskType || ''}
          label="Type"
          onChange={(e) => onChange({ ...filters, taskType: e.target.value || undefined })}
        >
          {TASK_TYPES.map((t) => (
            <MenuItem key={t.value} value={t.value}>
              {t.label}
            </MenuItem>
          ))}
        </Select>
      </FormControl>

      <FormControl size="small" sx={styles.select}>
        <InputLabel>Priority</InputLabel>
        <Select
          value={filters.priority || ''}
          label="Priority"
          onChange={(e) => onChange({ ...filters, priority: e.target.value || undefined })}
        >
          {PRIORITIES.map((p) => (
            <MenuItem key={p.value} value={p.value}>
              {p.label}
            </MenuItem>
          ))}
        </Select>
      </FormControl>

      <Autocomplete
        multiple
        freeSolo
        size="small"
        sx={styles.tags}
        options={[...COMMENT_TAG_SUGGESTIONS]}
        value={filters.tags || []}
        onChange={(_, newVal) => onChange({ ...filters, tags: newVal.length > 0 ? newVal : undefined })}
        renderTags={(value, getTagProps) =>
          value.map((option, index) => <Chip label={option} size="small" {...getTagProps({ index })} key={option} />)
        }
        renderInput={(params) => <TextField {...params} label="Tags" placeholder="Add tag" />}
      />

      <TextField
        size="small"
        sx={styles.search}
        placeholder="Search title..."
        value={filters.search || ''}
        onChange={(e) => onChange({ ...filters, search: e.target.value || undefined })}
        slotProps={{
          input: {
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon fontSize="small" />
              </InputAdornment>
            ),
          },
        }}
      />

      <PresetSelector
        currentFilters={filters}
        presets={allPresets}
        onApply={onChange}
        onSave={(name, shared) => {
          createPreset({
            projectId,
            boardViewPreset: { name, shared, filters: filters as unknown as Record<string, unknown> },
          });
        }}
        onDelete={(id) => deletePreset({ projectId, presetId: id })}
        currentUserId={currentUserId}
        hasActiveFilters={active}
      />

      {active && (
        <Button size="small" startIcon={<ClearIcon />} onClick={() => onChange({})}>
          Clear
        </Button>
      )}
    </Box>
  );
};
