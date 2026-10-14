import { Tooltip } from '@mantine/core';
import { IconInfoCircle } from '@tabler/icons-react';

interface InfoHintProps {
  label: string;
  size?: number;
  className?: string;
}

export function InfoHint({ label, size = 11, className }: InfoHintProps) {
  return (
    <Tooltip
      label={label}
      multiline
      maw={260}
      withArrow
      openDelay={150}
      events={{ hover: true, focus: true, touch: true }}
    >
      <span
        className={className}
        tabIndex={0}
        role="img"
        aria-label={label}
        style={{ display: 'inline-flex', alignItems: 'center', color: 'var(--text-3)', cursor: 'help' }}
      >
        <IconInfoCircle size={size} />
      </span>
    </Tooltip>
  );
}
