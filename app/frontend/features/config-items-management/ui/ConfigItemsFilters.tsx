import SearchIcon from '@mui/icons-material/Search';
import {
  FormControl,
  InputAdornment,
  InputLabel,
  MenuItem,
  Select,
  Stack,
  TextField,
  type SxProps,
} from '@mui/material';
import type { FC } from 'react';

import type { ConfigItemType, ConfigItemsFilters as Filters } from '../lib/types';

interface ConfigItemsFiltersProps {
  filters: Filters;
  onFilterChange: (filters: Filters) => void;
  searchValue: string;
  onSearchChange: (value: string) => void;
}

const styles = {
  searchField: {
    width: 300,
  },
  selectField: {
    width: 150,
  },
} satisfies Record<string, SxProps>;

const ConfigItemsFiltersComponent: FC<ConfigItemsFiltersProps> = ({
  filters,
  onFilterChange,
  searchValue,
  onSearchChange,
}) => {
  const handleTypeFilterChange = (type: ConfigItemType | '') => {
    onFilterChange({
      ...filters,
      itemType: type || undefined,
    });
  };

  return (
    <Stack direction="row" spacing={2} sx={{ mb: 3, flexWrap: 'wrap' }}>
      <TextField
        placeholder="Search by name..."
        value={searchValue}
        onChange={(e) => onSearchChange(e.target.value)}
        size="small"
        sx={styles.searchField}
        InputProps={{
          startAdornment: (
            <InputAdornment position="start">
              <SearchIcon />
            </InputAdornment>
          ),
        }}
      />

      <FormControl size="small" sx={styles.selectField}>
        <InputLabel size="small">Type</InputLabel>
        <Select
          value={filters.itemType || ''}
          label="Type"
          onChange={(e) => handleTypeFilterChange(e.target.value as ConfigItemType | '')}
        >
          <MenuItem value="">All Types</MenuItem>
          <MenuItem value="secret">Secret</MenuItem>
          <MenuItem value="variable">Variable</MenuItem>
        </Select>
      </FormControl>
    </Stack>
  );
};

export { ConfigItemsFiltersComponent as ConfigItemsFilters };
