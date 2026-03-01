import BookmarkIcon from '@mui/icons-material/Bookmark';
import DeleteIcon from '@mui/icons-material/Delete';
import SaveIcon from '@mui/icons-material/Save';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  FormControlLabel,
  IconButton,
  ListItemIcon,
  ListItemText,
  Menu,
  MenuItem,
  Switch,
  TextField,
  Typography,
} from '@mui/material';
import { useState } from 'react';

import type { BoardFilters } from './BoardFilterBar';

interface ViewPreset {
  id: number | string;
  name: string;
  filters: Record<string, unknown>;
  userId?: number;
  shared?: boolean;
  isBuiltIn?: boolean;
}

interface PresetSelectorProps {
  currentFilters: BoardFilters;
  presets: ViewPreset[];
  onApply: (filters: BoardFilters) => void;
  onSave: (name: string, shared: boolean) => void;
  onDelete: (id: number) => void;
  currentUserId?: number;
  hasActiveFilters: boolean;
}

export const PresetSelector = ({
  presets,
  onApply,
  onSave,
  onDelete,
  currentUserId,
  hasActiveFilters,
}: PresetSelectorProps) => {
  const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
  const [saveOpen, setSaveOpen] = useState(false);
  const [saveName, setSaveName] = useState('');
  const [saveShared, setSaveShared] = useState(false);

  const builtIn = presets.filter((p) => p.isBuiltIn);
  const saved = presets.filter((p) => !p.isBuiltIn);

  const handleApply = (preset: ViewPreset) => {
    onApply(preset.filters as BoardFilters);
    setAnchorEl(null);
  };

  const handleSave = () => {
    if (saveName.trim()) {
      onSave(saveName.trim(), saveShared);
      setSaveOpen(false);
      setSaveName('');
      setSaveShared(false);
    }
  };

  return (
    <>
      <Button size="small" startIcon={<BookmarkIcon />} onClick={(e) => setAnchorEl(e.currentTarget)}>
        Presets
      </Button>
      <Menu anchorEl={anchorEl} open={Boolean(anchorEl)} onClose={() => setAnchorEl(null)}>
        {builtIn.length > 0 && (
          <Box>
            <Typography
              sx={{
                px: 2,
                py: 0.5,
                fontSize: '11px',
                fontWeight: 600,
                color: 'text.disabled',
                textTransform: 'uppercase',
              }}
            >
              Built-in
            </Typography>
            {builtIn.map((p) => (
              <MenuItem key={p.id} onClick={() => handleApply(p)}>
                <ListItemText>{p.name}</ListItemText>
              </MenuItem>
            ))}
          </Box>
        )}
        {saved.length > 0 && (
          <Box>
            <Divider />
            <Typography
              sx={{
                px: 2,
                py: 0.5,
                fontSize: '11px',
                fontWeight: 600,
                color: 'text.disabled',
                textTransform: 'uppercase',
              }}
            >
              Saved
            </Typography>
            {saved.map((p) => (
              <MenuItem key={p.id} onClick={() => handleApply(p)}>
                <ListItemText>
                  {p.name}
                  {p.shared && (
                    <Typography component="span" sx={{ fontSize: '11px', color: 'text.disabled', ml: 0.5 }}>
                      (shared)
                    </Typography>
                  )}
                </ListItemText>
                {(p.userId === currentUserId || !p.userId) && typeof p.id === 'number' && (
                  <ListItemIcon sx={{ minWidth: 'auto', ml: 1 }}>
                    <IconButton
                      size="small"
                      onClick={(e) => {
                        e.stopPropagation();
                        onDelete(p.id as number);
                      }}
                    >
                      <DeleteIcon fontSize="small" />
                    </IconButton>
                  </ListItemIcon>
                )}
              </MenuItem>
            ))}
          </Box>
        )}
        <Divider />
        <MenuItem
          disabled={!hasActiveFilters}
          onClick={() => {
            setAnchorEl(null);
            setSaveOpen(true);
          }}
        >
          <ListItemIcon>
            <SaveIcon fontSize="small" />
          </ListItemIcon>
          <ListItemText>Save current filters</ListItemText>
        </MenuItem>
      </Menu>

      <Dialog open={saveOpen} onClose={() => setSaveOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>Save Filter Preset</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            label="Preset name"
            value={saveName}
            onChange={(e) => setSaveName(e.target.value)}
            sx={{ mt: 1 }}
          />
          <FormControlLabel
            control={<Switch checked={saveShared} onChange={(e) => setSaveShared(e.target.checked)} />}
            label="Share with team"
            sx={{ mt: 1 }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSaveOpen(false)}>Cancel</Button>
          <Button variant="contained" onClick={handleSave} disabled={!saveName.trim()}>
            Save
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
};
