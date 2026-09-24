import { ActionIcon, Box, Skeleton } from '@mantine/core';
import { IconX } from '@tabler/icons-react';

// Placeholder tab labels/widths — approximate real tab text ("Details", "Runs (3)", …) closely
// enough that the row's height and horizontal rhythm don't visibly shift once real tabs replace it.
const SKELETON_TAB_WIDTHS = [50, 70, 90, 60, 60, 70];

// Shown in place of the task detail panel while its data is still in flight (opening a card, or
// switching to a different one). Mirrors the real panel's header bar, tab row, and Details-tab
// layout — same paddings, same block sizes — so swapping in the loaded content changes what's
// drawn, not the panel's shape: no layout jump, no scroll reset, nothing to flash past.
export function TaskDetailSkeleton({ onClose }: { onClose: () => void }) {
  return (
    <>
      {/* Panel bar — same height/padding as the real one; only Close stays interactive. */}
      <Box
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 4,
          padding: '12px 16px',
          borderBottom: '1px solid var(--app-border-default)',
          flexShrink: 0,
        }}
      >
        <Skeleton height={20} width={20} radius="sm" />
        <Box style={{ flex: 1 }} />
        <Skeleton height={20} width={20} radius="sm" />
        <Skeleton height={20} width={20} radius="sm" />
        <ActionIcon variant="subtle" size="sm" title="Close" onClick={onClose}>
          <IconX size={16} />
        </ActionIcon>
      </Box>

      {/* Tab row */}
      <Box
        style={{
          display: 'flex',
          borderBottom: '1px solid var(--app-border-default)',
          paddingLeft: 16,
          paddingRight: 16,
          flexShrink: 0,
        }}
      >
        {SKELETON_TAB_WIDTHS.map((width, i) => (
          <Box key={i} style={{ padding: '9px 11px' }}>
            <Skeleton height={14} width={width} />
          </Box>
        ))}
      </Box>

      {/* Details tab: title, chips, description, then a properties list. */}
      <Box style={{ flex: 1, overflow: 'auto', padding: 20 }}>
        <Box style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 18 }}>
          <Skeleton height={26} width="65%" />
          <Box style={{ display: 'flex', gap: 7 }}>
            <Skeleton height={20} width={64} radius="sm" />
            <Skeleton height={20} width={78} radius="sm" />
          </Box>
          <Skeleton height={13} width="100%" />
          <Skeleton height={13} width="80%" />
        </Box>

        <Box>
          <Skeleton height={11} width={100} mb={14} />
          {[0, 1, 2, 3, 4].map((i) => (
            <Box
              key={i}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '11px 0',
                borderBottom: '1px solid rgba(41,39,38,0.4)',
              }}
            >
              <Skeleton height={12} width={70} />
              <Skeleton height={12} width={130} />
            </Box>
          ))}
        </Box>
      </Box>
    </>
  );
}
