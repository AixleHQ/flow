import { Checkbox, Combobox, Pill, PillsInput, ScrollArea, UnstyledButton, useCombobox } from '@mantine/core';
import { IconChevronRight } from '@tabler/icons-react';
import type { CSSProperties, KeyboardEvent, ReactNode } from 'react';
import { useMemo, useState } from 'react';

import {
  filterSections,
  sectionState,
  toggleSection,
  toggleTool,
  toolPickerPills,
  toolPickerSections,
  type ToolGroup,
  type ToolOption,
  type ToolPickerSection,
} from 'shared/lib/toolPicker';

import classes from './ToolPicker.module.css';

export interface ToolPickerProps {
  tools: ToolOption[];
  /** Tag groups this project offers; empty means a flat list of every tool. */
  groups?: ToolGroup[];
  value: number[];
  onChange: (toolIds: number[]) => void;
  label?: ReactNode;
  placeholder?: string;
  disabled?: boolean;
  /** Accessible name when the picker carries no visible label. */
  'aria-label'?: string;
  /** Per-call-site input chrome — the three pickers sit in three different shells. */
  inputStyles?: CSSProperties;
}

/** Clicking a control inside the dropdown must not blur the search field. */
const keepFocus = (event: { preventDefault: () => void }) => event.preventDefault();

/**
 * Tools picker for sessions and workflow steps.
 *
 * A tag group is a section, not an atom: its header attaches or clears the
 * whole family in one click, and the tools underneath are each attachable on
 * their own. The value is always the flat list of tool ids, so a group that is
 * half selected stays half selected.
 *
 * A group selected in full collapses to a single chip; anything else shows one
 * chip per tool, which is the only honest rendering of a subset.
 */
export function ToolPicker({
  tools,
  groups = [],
  value,
  onChange,
  label,
  placeholder,
  disabled = false,
  'aria-label': ariaLabel,
  inputStyles,
}: ToolPickerProps) {
  const [search, setSearch] = useState('');
  // Only the sections the user has explicitly opened or closed; everything else
  // follows the default below, so a section can react to search and selection.
  const [expandOverrides, setExpandOverrides] = useState<Record<string, boolean>>({});

  const combobox = useCombobox({
    onDropdownClose: () => {
      combobox.resetSelectedOption();
      setSearch('');
    },
  });

  const sections = useMemo(() => toolPickerSections(tools, groups), [tools, groups]);
  const visibleSections = useMemo(() => filterSections(sections, search), [sections, search]);
  const pills = useMemo(() => toolPickerPills(sections, value), [sections, value]);

  const searching = search.trim() !== '';
  const selected = new Set(value);

  // Open while searching (the match is the point) and whenever a group is only
  // partly attached — a "3/8" that cannot be inspected is a dead end.
  const isExpanded = (section: ToolPickerSection) =>
    expandOverrides[section.key] ?? (searching || sectionState(section, value) === 'partial');

  const setExpanded = (key: string, expanded: boolean) =>
    setExpandOverrides((current) => ({ ...current, [key]: expanded }));

  const handleOptionSubmit = (optionValue: string) => {
    onChange(toggleTool(Number(optionValue), value));
  };

  const removePill = (toolIds: number[]) => {
    const dropped = new Set(toolIds);
    onChange(value.filter((id) => !dropped.has(id)));
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key !== 'Backspace' || search !== '' || pills.length === 0) return;

    event.preventDefault();
    removePill(pills[pills.length - 1].toolIds);
  };

  const renderTool = (tool: ToolOption, nested: boolean) => {
    const attached = selected.has(tool.id);

    return (
      // Mantine's `selected` only styles the row; the attached/detached state is
      // the whole point of this list, so it is spelled out for assistive tech.
      <Combobox.Option value={String(tool.id)} key={tool.id} selected={attached} aria-selected={attached}>
        <div className={`${classes.toolOption} ${nested ? classes.toolOptionNested : ''}`}>
          <Checkbox.Indicator checked={attached} size="xs" />
          <span>{tool.name}</span>
        </div>
      </Combobox.Option>
    );
  };

  const renderSection = (section: ToolPickerSection) => {
    // No groups offered at all — the picker is a plain list, as it was before
    // groups existed, and an "Ungrouped" heading over everything would be noise.
    if (section.ungrouped && sections.length === 1) {
      return section.tools.map((tool) => renderTool(tool, false));
    }

    if (section.ungrouped) {
      return [
        <div className={classes.ungroupedLabel} key={section.key}>
          {section.label}
        </div>,
        ...section.tools.map((tool) => renderTool(tool, false)),
      ];
    }

    const state = sectionState(section, value);
    const expanded = isExpanded(section);
    const attached = section.tools.filter((t) => selected.has(t.id)).length;

    return [
      <div className={classes.groupRow} key={section.key}>
        <UnstyledButton
          className={classes.chevron}
          aria-label={`${expanded ? 'Collapse' : 'Expand'} ${section.label}`}
          aria-expanded={expanded}
          onMouseDown={keepFocus}
          onClick={() => setExpanded(section.key, !expanded)}
        >
          <IconChevronRight size={12} className={`${classes.chevronIcon} ${expanded ? classes.chevronIconOpen : ''}`} />
        </UnstyledButton>
        <UnstyledButton
          className={classes.groupToggle}
          role="checkbox"
          aria-checked={state === 'all' ? true : state === 'partial' ? 'mixed' : false}
          disabled={disabled}
          onMouseDown={keepFocus}
          onClick={() => {
            // Pin the current fold state: completing a group would otherwise
            // drop it back to the collapsed default under the user's cursor.
            setExpanded(section.key, expanded);
            onChange(toggleSection(section, value));
          }}
        >
          <Checkbox.Indicator checked={state !== 'none'} indeterminate={state === 'partial'} size="xs" />
          <span className={classes.groupLabel}>{section.label}</span>
          {/* While filtering, the header only reaches the matches — say so, or
              "6/6" reads as a group that is fully attached. */}
          <span className={classes.count}>
            {attached}/{section.tools.length}
            {searching ? ' matched' : ''}
          </span>
        </UnstyledButton>
      </div>,
      ...(expanded ? section.tools.map((tool) => renderTool(tool, true)) : []),
    ];
  };

  return (
    <Combobox
      store={combobox}
      position="bottom-start"
      shadow="md"
      withinPortal
      readOnly={disabled}
      // Tools are picked as a set: submitting an option toggles it and leaves
      // the dropdown open so a whole family can be assembled in one pass.
      onOptionSubmit={handleOptionSubmit}
    >
      <Combobox.DropdownTarget>
        <PillsInput
          label={label}
          disabled={disabled}
          onClick={() => !disabled && combobox.openDropdown()}
          rightSection={<Combobox.Chevron />}
          rightSectionPointerEvents="none"
          styles={inputStyles ? { input: inputStyles } : undefined}
        >
          <Pill.Group>
            {pills.map((pill) => (
              <Pill
                key={pill.key}
                withRemoveButton={!disabled}
                // Mantine hides the remove button from assistive tech, on the
                // assumption that pills are unpicked from the dropdown. A group
                // chip has no single option to unpick, so it stays reachable.
                removeButtonProps={{ 'aria-label': `Remove ${pill.label}`, 'aria-hidden': false }}
                onRemove={() => removePill(pill.toolIds)}
              >
                {pill.label}
              </Pill>
            ))}
            <Combobox.EventsTarget withExpandedAttribute>
              <PillsInput.Field
                value={search}
                placeholder={pills.length === 0 ? placeholder : undefined}
                aria-label={ariaLabel}
                disabled={disabled}
                onChange={(event) => {
                  combobox.openDropdown();
                  combobox.updateSelectedOptionIndex();
                  setSearch(event.currentTarget.value);
                }}
                onFocus={() => !disabled && combobox.openDropdown()}
                onBlur={() => combobox.closeDropdown()}
                onKeyDown={handleKeyDown}
              />
            </Combobox.EventsTarget>
          </Pill.Group>
        </PillsInput>
      </Combobox.DropdownTarget>

      <Combobox.Dropdown>
        <Combobox.Options>
          <ScrollArea.Autosize mah={280} type="scroll">
            {visibleSections.length === 0 ? (
              <Combobox.Empty>No tools found</Combobox.Empty>
            ) : (
              visibleSections.map(renderSection)
            )}
          </ScrollArea.Autosize>
        </Combobox.Options>
      </Combobox.Dropdown>
    </Combobox>
  );
}
