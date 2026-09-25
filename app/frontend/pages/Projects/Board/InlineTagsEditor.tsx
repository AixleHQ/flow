import { Box, Combobox, ScrollArea, Text, useCombobox } from '@mantine/core';
import { useMemo, useRef, useState } from 'react';

// --- Inline tags editor (matches reference .tag / .add-tag / .tag-input pattern) ---

export function InlineTagsEditor({
  tags,
  onChange,
  disabled,
  suggestions,
}: {
  tags: string[];
  onChange: (tags: string[]) => void;
  disabled?: boolean;
  suggestions?: string[];
}) {
  const [inputVisible, setInputVisible] = useState(false);
  const [inputValue, setInputValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const combobox = useCombobox({ onDropdownClose: () => combobox.resetSelectedOption() });

  // Tags the board already uses, minus the ones on this task — picking from these is what keeps
  // "frontend" from silently becoming "front-end" on the next task.
  const options = useMemo(() => {
    const query = inputValue.trim().toLowerCase();
    return (suggestions ?? []).filter((s) => !tags.includes(s) && (query === '' || s.toLowerCase().includes(query)));
  }, [suggestions, tags, inputValue]);

  const showInput = () => {
    setInputVisible(true);
    setTimeout(() => inputRef.current?.focus(), 0);
  };

  const addTag = (tag: string) => {
    if (tag && !tags.includes(tag)) onChange([...tags, tag]);
    setInputValue('');
    setInputVisible(false);
    combobox.closeDropdown();
  };

  const commitTag = () => addTag(inputValue.trim());

  const removeTag = (tag: string) => onChange(tags.filter((t) => t !== tag));

  return (
    <Box style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', marginLeft: -9 }}>
      {tags.map((tag) => (
        <Box
          key={tag}
          style={{
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: '0.02em',
            padding: '4px 5px 4px 9px',
            borderRadius: 5,
            border: '1px solid rgba(209,207,205,0.14)',
            background: 'rgba(209,207,205,0.05)',
            color: 'var(--mantine-color-dimmed)',
            display: 'inline-flex',
            alignItems: 'center',
            gap: 2,
            whiteSpace: 'nowrap',
            lineHeight: 1,
          }}
        >
          {tag}
          {!disabled && (
            <Box
              component="button"
              onClick={() => removeTag(tag)}
              style={{
                cursor: 'pointer',
                fontSize: 12,
                opacity: 0.5,
                width: 16,
                height: 16,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                borderRadius: 3,
                background: 'none',
                border: 'none',
                color: 'inherit',
                padding: 0,
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLButtonElement).style.opacity = '1';
                (e.currentTarget as HTMLButtonElement).style.color = 'var(--app-danger-fg)';
                (e.currentTarget as HTMLButtonElement).style.background = 'rgba(200,90,90,0.12)';
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLButtonElement).style.opacity = '0.5';
                (e.currentTarget as HTMLButtonElement).style.color = 'inherit';
                (e.currentTarget as HTMLButtonElement).style.background = 'none';
              }}
            >
              ×
            </Box>
          )}
        </Box>
      ))}
      {!disabled && !inputVisible && (
        <Box
          component="button"
          onClick={showInput}
          style={{
            fontSize: 11,
            fontWeight: 500,
            letterSpacing: '0.02em',
            padding: '4px 10px',
            borderRadius: 5,
            border: '1px dashed var(--app-border-strong)',
            background: 'transparent',
            color: 'var(--mantine-color-placeholder)',
            cursor: 'pointer',
            lineHeight: 1,
            transition: 'color 0.12s, border-color 0.12s',
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--mantine-color-dimmed)';
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--mantine-color-dimmed)';
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.color = 'var(--mantine-color-placeholder)';
            (e.currentTarget as HTMLButtonElement).style.borderColor = 'var(--app-border-strong)';
          }}
        >
          + Add
        </Box>
      )}
      {!disabled && inputVisible && (
        <Combobox store={combobox} position="bottom-start" shadow="md" withinPortal onOptionSubmit={addTag}>
          <Combobox.Target>
            <input
              ref={inputRef}
              value={inputValue}
              aria-label="Tag name"
              onFocus={() => combobox.openDropdown()}
              onChange={(e) => {
                setInputValue(e.currentTarget.value);
                combobox.openDropdown();
                combobox.resetSelectedOption();
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  // An arrow-key-highlighted suggestion wins over the raw text: Mantine's own
                  // handler runs right after this one and submits the option.
                  if (combobox.getSelectedOptionIndex() !== -1) return;
                  e.preventDefault();
                  commitTag();
                }
                if (e.key === 'Escape') {
                  // First Escape dismisses the suggestions, a second one leaves the input.
                  if (combobox.dropdownOpened) return;
                  e.preventDefault();
                  setInputValue('');
                  setInputVisible(false);
                }
              }}
              onBlur={() => {
                // Only commit on blur if still in input mode (Escape key sets inputVisible=false)
                if (inputVisible) commitTag();
              }}
              placeholder="Tag name"
              style={{
                width: 120,
                background: 'var(--app-bg-paper)',
                border: '1px solid var(--app-primary)',
                borderRadius: 5,
                fontFamily: 'inherit',
                fontSize: 12,
                padding: '4px 10px',
                lineHeight: 1,
                color: 'var(--mantine-color-text)',
                outline: 'none',
              }}
            />
          </Combobox.Target>
          <Combobox.Dropdown hidden={options.length === 0}>
            <Combobox.Options>
              <ScrollArea.Autosize mah={180} type="scroll">
                {options.map((tag) => (
                  <Combobox.Option value={tag} key={tag}>
                    <Text size="xs">{tag}</Text>
                  </Combobox.Option>
                ))}
              </ScrollArea.Autosize>
            </Combobox.Options>
          </Combobox.Dropdown>
        </Combobox>
      )}
    </Box>
  );
}
