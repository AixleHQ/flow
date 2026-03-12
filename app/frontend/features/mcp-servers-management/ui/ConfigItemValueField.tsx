import KeyIcon from '@mui/icons-material/Key';
import TextFieldsIcon from '@mui/icons-material/TextFields';
import { Autocomplete, IconButton, TextField, Tooltip } from '@mui/material';
import { useEffect, useState, type FC } from 'react';

import { useGetCompanyConfigItemsForSelectQuery } from 'shared/api';

const CONFIG_ITEM_PREFIX = 'config_item:';

interface ConfigItemValueFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
}

export const ConfigItemValueField: FC<ConfigItemValueFieldProps> = ({
  value,
  onChange,
  placeholder,
  label = 'Value',
}) => {
  const isRef = value.startsWith(CONFIG_ITEM_PREFIX);
  const [useConfigItem, setUseConfigItem] = useState(isRef);

  const { data: configItems = [] } = useGetCompanyConfigItemsForSelectQuery(undefined, {
    skip: !useConfigItem,
  });

  useEffect(() => {
    setUseConfigItem(value.startsWith(CONFIG_ITEM_PREFIX));
  }, [value]);

  const selectedName = isRef ? value.slice(CONFIG_ITEM_PREFIX.length) : '';

  const handleToggle = () => {
    if (useConfigItem) {
      onChange('');
      setUseConfigItem(false);
    } else {
      onChange('');
      setUseConfigItem(true);
    }
  };

  if (useConfigItem) {
    const options = configItems.map((ci) => ci.name);

    return (
      <>
        <Autocomplete
          size="small"
          options={options}
          value={options.includes(selectedName) ? selectedName : null}
          onChange={(_e, newValue) => {
            onChange(newValue ? `${CONFIG_ITEM_PREFIX}${newValue}` : '');
          }}
          renderInput={(params) => (
            <TextField
              {...params}
              label={label}
              placeholder="Select config item..."
              sx={{ '& input': { fontFamily: 'monospace' } }}
            />
          )}
          fullWidth
          freeSolo={false}
        />
        <Tooltip title="Switch to plain text">
          <IconButton size="small" onClick={handleToggle} color="primary">
            <TextFieldsIcon fontSize="small" />
          </IconButton>
        </Tooltip>
      </>
    );
  }

  return (
    <>
      <TextField
        label={label}
        size="small"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        fullWidth
        sx={{ '& input': { fontFamily: 'monospace' } }}
      />
      <Tooltip title="Use value from Config Items">
        <IconButton size="small" onClick={handleToggle}>
          <KeyIcon fontSize="small" />
        </IconButton>
      </Tooltip>
    </>
  );
};
