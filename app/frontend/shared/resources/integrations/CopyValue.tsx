import { ActionIcon, CopyButton, Tooltip } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';

export const CopyValue = ({ label, value }: { label: string; value: string }) => (
  <CopyButton value={value}>
    {({ copied, copy }) => (
      <Tooltip label={copied ? 'Copied' : `Copy ${label.toLowerCase()}`}>
        <ActionIcon aria-label={`Copy ${label.toLowerCase()}`} variant="subtle" size="sm" color="gray" onClick={copy}>
          {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
        </ActionIcon>
      </Tooltip>
    )}
  </CopyButton>
);
