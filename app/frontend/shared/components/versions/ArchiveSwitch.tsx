import { SegmentedControl } from '@mantine/core';

export type ArchiveView = 'active' | 'archived';

interface ArchiveSwitchProps {
  value: ArchiveView;
  onChange: (value: ArchiveView) => void;
  activeCount: number;
  archivedCount: number;
}

/** Switches a list screen between its live entities and its archive. */
export function ArchiveSwitch({ value, onChange, activeCount, archivedCount }: ArchiveSwitchProps) {
  return (
    <SegmentedControl
      aria-label="Show active or archived"
      value={value}
      onChange={(next) => onChange(next as ArchiveView)}
      data={[
        { value: 'active', label: `Active (${activeCount})` },
        { value: 'archived', label: `Archived (${archivedCount})` },
      ]}
    />
  );
}
