import { Box, Checkbox, Combobox, Group, ScrollArea, Text, useCombobox } from '@mantine/core';
import { IconChevronDown, IconFile, IconFolder, IconHome } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { useMemo, useState } from 'react';

import { assetFolder, derivedFolderPaths, descendantAssetIds } from 'shared/resources/assets/folderTree';

export interface AssetPickerItem {
  id: number;
  name: string;
  folder?: string | null;
}

interface AssetPickerProps {
  assets: AssetPickerItem[];
  value: number[];
  onChange: (ids: number[]) => void;
  disabled?: boolean;
  label?: ReactNode;
  placeholder?: string;
  'aria-label'?: string;
}

const FOLDER_PREFIX = 'folder:';
const ASSET_PREFIX = 'asset:';

interface Group {
  /** '' for the root group. */
  path: string;
  files: AssetPickerItem[];
}

/**
 * A folder-grouped, searchable combobox for attaching assets to a workflow/step/session — the
 * folder-aware replacement for a plain `<MultiSelect>` (per the Assets folder view, #564).
 *
 * Storage is unchanged: `value`/`onChange` are still just an array of asset ids. Selecting a
 * folder's header is a *bulk* toggle of every asset (transitively) under it — it does not add a
 * "whole folder" as a distinct value, so there is nothing to resolve at session-run time. A
 * folder with no assets under it can't exist in the data this component is given (folders here
 * are derived purely from `asset.folder`), so empty folders never appear.
 */
export function AssetPicker({
  assets,
  value,
  onChange,
  disabled,
  label,
  placeholder = 'Select assets…',
  'aria-label': ariaLabel,
}: AssetPickerProps) {
  const [search, setSearch] = useState('');
  const combobox = useCombobox({
    onDropdownClose: () => {
      combobox.resetSelectedOption();
      setSearch('');
    },
    onDropdownOpen: () => combobox.focusSearchInput(),
  });

  const groups = useMemo(() => buildGroups(assets, search), [assets, search]);
  const selected = useMemo(() => new Set(value), [value]);

  const toggleAsset = (id: number) => {
    onChange(selected.has(id) ? value.filter((v) => v !== id) : [...value, id]);
  };

  const toggleFolder = (path: string) => {
    const ids = descendantAssetIds(assets, path);
    const allSelected = ids.every((id) => selected.has(id));
    onChange(allSelected ? value.filter((v) => !ids.includes(v)) : [...new Set([...value, ...ids])]);
  };

  return (
    <Combobox
      store={combobox}
      shadow="md"
      withinPortal
      onOptionSubmit={(optionValue) => {
        if (optionValue.startsWith(FOLDER_PREFIX)) {
          toggleFolder(optionValue.slice(FOLDER_PREFIX.length));
        } else {
          toggleAsset(Number(optionValue.slice(ASSET_PREFIX.length)));
        }
      }}
    >
      <Combobox.Target targetType="button">
        <Box
          component="button"
          type="button"
          aria-label={ariaLabel ?? (typeof label === 'string' ? label : 'Select assets')}
          disabled={disabled}
          onClick={() => combobox.toggleDropdown()}
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 8,
            width: '100%',
            background: 'var(--app-bg-card, var(--mantine-color-body))',
            border: '1px solid var(--app-border-default, var(--mantine-color-default-border))',
            borderRadius: 'var(--mantine-radius-md)',
            color: value.length === 0 ? 'var(--mantine-color-placeholder)' : 'var(--mantine-color-text)',
            font: 'inherit',
            fontSize: 14,
            padding: '8px 11px',
            cursor: disabled ? 'not-allowed' : 'pointer',
            opacity: disabled ? 0.6 : 1,
          }}
        >
          <span>{value.length === 0 ? placeholder : `${value.length} selected`}</span>
          <IconChevronDown size={14} style={{ flexShrink: 0, opacity: 0.6 }} />
        </Box>
      </Combobox.Target>

      <Combobox.Dropdown>
        <Combobox.Search
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          placeholder="Search files or folders…"
          aria-label="Search assets"
        />
        <Combobox.Options>
          <ScrollArea.Autosize mah={280} type="scroll">
            {groups.length === 0 ? (
              <Combobox.Empty>{search ? `No files or folders match "${search}"` : 'No assets yet'}</Combobox.Empty>
            ) : (
              groups.map((group) => (
                <FolderGroup key={group.path || 'root'} group={group} assets={assets} selected={selected} />
              ))
            )}
          </ScrollArea.Autosize>
        </Combobox.Options>
      </Combobox.Dropdown>
    </Combobox>
  );
}

function FolderGroup({ group, assets, selected }: { group: Group; assets: AssetPickerItem[]; selected: Set<number> }) {
  if (!group.path) {
    return (
      <Box>
        <Group gap={4} wrap="nowrap" px={10} pt={6} c="dimmed">
          <IconHome size={11} />
          <Text size="xs" fw={600} tt="uppercase" style={{ letterSpacing: 0.4 }}>
            Root
          </Text>
        </Group>
        {group.files.map((file) => (
          <AssetOption key={file.id} file={file} selected={selected.has(file.id)} />
        ))}
      </Box>
    );
  }

  const ids = descendantAssetIds(assets, group.path);
  const selectedCount = ids.filter((id) => selected.has(id)).length;
  const checked = ids.length > 0 && selectedCount === ids.length;
  const indeterminate = selectedCount > 0 && !checked;

  return (
    <Box>
      <Combobox.Option value={`${FOLDER_PREFIX}${group.path}`} active={checked}>
        <Group gap={6} wrap="nowrap">
          <Checkbox
            checked={checked}
            indeterminate={indeterminate}
            readOnly
            size="xs"
            tabIndex={-1}
            aria-hidden
            style={{ pointerEvents: 'none' }}
          />
          <IconFolder size={13} />
          <Text size="xs" fw={600} style={{ wordBreak: 'break-word' }}>
            {group.path}
          </Text>
        </Group>
      </Combobox.Option>
      {group.files.map((file) => (
        <AssetOption key={file.id} file={file} selected={selected.has(file.id)} />
      ))}
    </Box>
  );
}

function AssetOption({ file, selected }: { file: AssetPickerItem; selected: boolean }) {
  return (
    <Combobox.Option value={`${ASSET_PREFIX}${file.id}`} active={selected}>
      <Group gap={6} wrap="nowrap" pl={18}>
        <Checkbox checked={selected} readOnly size="xs" tabIndex={-1} aria-hidden style={{ pointerEvents: 'none' }} />
        <IconFile size={13} style={{ flexShrink: 0, opacity: 0.7 }} />
        <Text size="xs" style={{ wordBreak: 'break-word' }}>
          {file.name}
        </Text>
      </Group>
    </Combobox.Option>
  );
}

function buildGroups(assets: AssetPickerItem[], query: string): Group[] {
  const q = query.trim().toLowerCase();
  const paths = derivedFolderPaths(assets);

  const matches = assets.filter((a) => {
    if (!q) return true;
    const folder = assetFolder(a);
    const fullPath = folder ? `${folder}/${a.name}` : a.name;
    return a.name.toLowerCase().includes(q) || fullPath.toLowerCase().includes(q);
  });

  const byFolder = new Map<string, AssetPickerItem[]>();
  matches.forEach((a) => {
    const folder = assetFolder(a);
    byFolder.set(folder, [...(byFolder.get(folder) ?? []), a]);
  });

  // A folder whose name matches the query still shows (with its own direct files, possibly none),
  // even when none of ITS files individually matched — mirrors the reference picker.
  if (q) {
    paths.forEach((path) => {
      if (path.toLowerCase().includes(q) && !byFolder.has(path)) byFolder.set(path, []);
    });
  }

  const groups: Group[] = [];
  const root = byFolder.get('');
  if (root?.length) groups.push({ path: '', files: root });

  [...byFolder.keys()]
    .filter((path) => path !== '')
    .sort((a, b) => a.localeCompare(b))
    .forEach((path) => groups.push({ path, files: byFolder.get(path) ?? [] }));

  return groups;
}
