import { Checkbox, Stack, Text } from '@mantine/core';

import { CAPABILITIES } from './azureDevopsShared';

interface CapabilityPickerProps {
  value: string[];
  onChange: (value: string[]) => void;
}

export const CapabilityPicker = ({ value, onChange }: CapabilityPickerProps) => (
  <Checkbox.Group
    label="What agents may do"
    description="Unticking one stops Aixle sending that kind of request at all. Azure still decides separately whether the identity is permitted."
    value={value}
    onChange={onChange}
  >
    <Stack gap={6} mt="xs">
      {CAPABILITIES.map((capability) => (
        <Checkbox
          key={capability.value}
          value={capability.value}
          label={
            <span>
              {capability.label}{' '}
              <Text component="span" fz={12} c="dimmed">
                — {capability.hint}
              </Text>
            </span>
          }
        />
      ))}
    </Stack>
  </Checkbox.Group>
);
