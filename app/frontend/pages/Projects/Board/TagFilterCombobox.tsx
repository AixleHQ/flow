import { Button, Combobox, Group, ScrollArea, Text, useCombobox } from '@mantine/core';
import { IconCheck, IconTag } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

// A board accumulates tags without bound, so the filter is a searchable combobox rather than a
// plain menu: type to narrow, arrows + Enter to pick, and the option list scrolls instead of
// growing past the viewport — every tag stays reachable no matter how many there are.
export function TagFilterCombobox({
  allTags,
  selected,
  onToggle,
  onClear,
}: {
  allTags: string[];
  selected: string[];
  onToggle: (tag: string) => void;
  onClear: () => void;
}) {
  const [search, setSearch] = useState('');
  const combobox = useCombobox({
    onDropdownClose: () => {
      combobox.resetSelectedOption();
      setSearch('');
    },
    // Focus the search box on open so typing filters immediately, without a second click.
    onDropdownOpen: () => combobox.focusSearchInput(),
  });

  const matches = useMemo(() => {
    const query = search.trim().toLowerCase();
    return query ? allTags.filter((tag) => tag.toLowerCase().includes(query)) : allTags;
  }, [allTags, search]);

  const label = selected.length === 0 ? 'All' : selected.length === 1 ? selected[0] : `${selected.length} selected`;

  return (
    <Combobox
      store={combobox}
      width={240}
      position="bottom-start"
      shadow="md"
      withinPortal
      // Tags filter as a set, so submitting an option toggles it and leaves the dropdown open —
      // several tags can be picked in one pass.
      onOptionSubmit={(tag) => onToggle(tag)}
    >
      <Combobox.Target targetType="button">
        <Button
          variant="default"
          size="xs"
          leftSection={<IconTag size={12} />}
          onClick={() => combobox.toggleDropdown()}
          styles={{
            root: {
              fontWeight: 400,
              color: selected.length > 0 ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
            },
          }}
        >
          Tags: {label}
        </Button>
      </Combobox.Target>

      <Combobox.Dropdown>
        <Combobox.Search
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          placeholder="Search tags"
          aria-label="Search tags"
        />
        <Combobox.Options>
          <ScrollArea.Autosize mah={240} type="scroll">
            {matches.length === 0 ? (
              <Combobox.Empty>No tags found</Combobox.Empty>
            ) : (
              matches.map((tag) => {
                const isSelected = selected.includes(tag);
                return (
                  <Combobox.Option value={tag} key={tag} active={isSelected}>
                    <Group gap={6} wrap="nowrap">
                      <IconCheck size={12} style={{ flexShrink: 0, visibility: isSelected ? 'visible' : 'hidden' }} />
                      <Text size="xs" fw={isSelected ? 600 : 400} style={{ wordBreak: 'break-word' }}>
                        {tag}
                      </Text>
                    </Group>
                  </Combobox.Option>
                );
              })
            )}
          </ScrollArea.Autosize>
        </Combobox.Options>
        {selected.length > 0 && (
          <Combobox.Footer>
            <Button variant="subtle" color="gray" size="compact-xs" onClick={onClear}>
              Clear tags
            </Button>
          </Combobox.Footer>
        )}
      </Combobox.Dropdown>
    </Combobox>
  );
}
