import { ActionIcon, Autocomplete, TextInput, Tooltip } from '@mantine/core';
import { IconKey, IconLetterCase } from '@tabler/icons-react';
import { useEffect, useState, type FC } from 'react';

const CONFIG_ITEM_PREFIX = 'config_item:';

interface ConfigItemValueFieldProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  label?: string;
  configItemNames: string[];
}

export const ConfigItemValueField: FC<ConfigItemValueFieldProps> = ({
  value,
  onChange,
  placeholder,
  label = 'Value',
  configItemNames,
}) => {
  const isRef = value.startsWith(CONFIG_ITEM_PREFIX);
  const [useConfigItem, setUseConfigItem] = useState(isRef);

  useEffect(() => {
    setUseConfigItem(value.startsWith(CONFIG_ITEM_PREFIX));
  }, [value]);

  const selectedName = isRef ? value.slice(CONFIG_ITEM_PREFIX.length) : '';

  const handleToggle = () => {
    onChange('');
    setUseConfigItem(!useConfigItem);
  };

  if (useConfigItem) {
    return (
      <>
        <Autocomplete
          size="sm"
          data={configItemNames}
          value={selectedName}
          onChange={(val) => onChange(val ? `${CONFIG_ITEM_PREFIX}${val}` : '')}
          label={label}
          placeholder="Select config item..."
          styles={{ input: { fontFamily: 'monospace' } }}
          style={{ flex: 1 }}
        />
        <Tooltip label="Switch to plain text">
          {/* Icon-only, so the tooltip is not enough: a tooltip is not an
              accessible name and never reaches a screen reader. */}
          <ActionIcon
            variant="subtle"
            size="sm"
            aria-label="Switch to plain text"
            onClick={handleToggle}
            mt={label ? 24 : 0}
          >
            <IconLetterCase size={16} />
          </ActionIcon>
        </Tooltip>
      </>
    );
  }

  return (
    <>
      <TextInput
        label={label}
        size="sm"
        value={value}
        onChange={(e) => onChange(e.currentTarget.value)}
        placeholder={placeholder}
        styles={{ input: { fontFamily: 'monospace' } }}
        style={{ flex: 1 }}
      />
      <Tooltip label="Use value from Secrets & Variables">
        <ActionIcon
          variant="subtle"
          size="sm"
          aria-label="Use value from Secrets & Variables"
          onClick={handleToggle}
          mt={label ? 24 : 0}
        >
          <IconKey size={16} />
        </ActionIcon>
      </Tooltip>
    </>
  );
};
