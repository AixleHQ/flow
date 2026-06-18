import data from '@emoji-mart/data';
import Picker from '@emoji-mart/react';
import { Box, Popover, UnstyledButton } from '@mantine/core';
import { useState, type FC } from 'react';

interface EmojiPickerProps {
  value: string;
  onChange: (emoji: string) => void;
  disabled?: boolean;
}

interface EmojiData {
  native: string;
}

export const EmojiPicker: FC<EmojiPickerProps> = ({ value, onChange, disabled }) => {
  const [opened, setOpened] = useState(false);

  const handleEmojiSelect = (emoji: EmojiData) => {
    onChange(emoji.native);
    setOpened(false);
  };

  return (
    <Popover opened={opened} onChange={setOpened} position="bottom-start" shadow="md">
      <Popover.Target>
        <UnstyledButton
          onClick={() => !disabled && setOpened((o) => !o)}
          style={{
            width: 56,
            height: 56,
            fontSize: 28,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            border: '1px solid rgba(255, 255, 255, 0.23)',
            borderRadius: 'var(--mantine-radius-sm)',
            backgroundColor: 'transparent',
            marginTop: 25,
            cursor: disabled ? 'default' : 'pointer',
            opacity: disabled ? 0.5 : 1,
          }}
        >
          {value || (
            <Box
              style={{
                fontSize: 12,
                color: 'var(--app-text-tertiary)',
              }}
            >
              Icon
            </Box>
          )}
        </UnstyledButton>
      </Popover.Target>
      <Popover.Dropdown p={0} style={{ border: 'none', background: 'transparent' }}>
        <Picker
          data={data}
          onEmojiSelect={handleEmojiSelect}
          theme="dark"
          previewPosition="none"
          skinTonePosition="search"
        />
      </Popover.Dropdown>
    </Popover>
  );
};
