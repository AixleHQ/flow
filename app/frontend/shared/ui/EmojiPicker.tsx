import { Box, Popover, SimpleGrid, TextInput, UnstyledButton } from '@mantine/core';
import { useState, type FC } from 'react';

interface EmojiPickerProps {
  value: string;
  onChange: (emoji: string) => void;
  disabled?: boolean;
}

// An agent's icon, not a messaging emoji keyboard: a short set covers it, and any
// other emoji can be typed or pasted. It replaced emoji-mart, whose React binding
// supports React up to 18 and whose data file alone was 432 KB.
const EMOJIS = [
  '🤖',
  '🧠',
  '🛠️',
  '⚙️',
  '🔧',
  '🧪',
  '🔬',
  '📐',
  '📊',
  '📈',
  '🗂️',
  '📝',
  '✍️',
  '📚',
  '🔍',
  '🧭',
  '🚀',
  '🛰️',
  '🛡️',
  '🔒',
  '🔑',
  '🧩',
  '🎯',
  '⚡',
  '🔥',
  '🌱',
  '🌊',
  '☁️',
  '🐛',
  '🦉',
  '🐙',
  '🦊',
  '🐝',
  '🦾',
  '👩‍💻',
  '👨‍💻',
  '🧑‍🔬',
  '🧑‍🎨',
  '🎨',
  '💡',
  '📦',
  '🏗️',
  '🧹',
  '🗺️',
  '📣',
  '💬',
  '✅',
  '⭐',
];

export const EmojiPicker: FC<EmojiPickerProps> = ({ value, onChange, disabled }) => {
  const [opened, setOpened] = useState(false);

  const choose = (emoji: string) => {
    onChange(emoji);
    setOpened(false);
  };

  return (
    <Popover opened={opened} onChange={setOpened} position="bottom-start" shadow="md">
      <Popover.Target>
        <UnstyledButton
          onClick={() => !disabled && setOpened((o) => !o)}
          aria-label={value ? `Icon ${value}, change` : 'Choose an icon'}
          style={{
            width: 56,
            height: 56,
            fontSize: 28,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            border: '1px solid var(--app-border-default)',
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
      <Popover.Dropdown p="xs">
        <SimpleGrid cols={8} spacing={4} verticalSpacing={4}>
          {EMOJIS.map((emoji) => (
            <UnstyledButton
              key={emoji}
              onClick={() => choose(emoji)}
              aria-label={emoji}
              style={{ fontSize: 20, lineHeight: '32px', width: 32, textAlign: 'center', borderRadius: 4 }}
            >
              {emoji}
            </UnstyledButton>
          ))}
        </SimpleGrid>
        <TextInput
          mt="xs"
          size="xs"
          placeholder="Or type or paste any emoji"
          aria-label="Custom icon"
          onKeyDown={(event) => {
            const typed = event.currentTarget.value.trim();
            if (event.key === 'Enter' && typed) {
              event.preventDefault();
              choose(typed);
            }
          }}
        />
      </Popover.Dropdown>
    </Popover>
  );
};
