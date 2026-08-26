import { ActionIcon, Group, Tooltip } from '@mantine/core';
import {
  IconAlertHexagon,
  IconAlertTriangle,
  IconArrowUpCircle,
  IconLockOpen,
  IconShieldQuestion,
} from '@tabler/icons-react';
import type { FC } from 'react';

import { serverHealthSignals, type ServerHealthSignal } from './serverHealth';
import type { McpServer } from './types';

// Health reads as one glyph per fact, sitting with the server's name. In a
// dense table the alternative — a badge per condition — would double the row's
// visual weight for information most rows do not carry.
const ICON: Record<ServerHealthSignal['kind'], typeof IconAlertTriangle> = {
  drift: IconAlertTriangle,
  delisted: IconAlertHexagon,
  unpinned: IconLockOpen,
  unverified: IconShieldQuestion,
  update: IconArrowUpCircle,
};

const COLOR: Record<ServerHealthSignal['level'], string> = {
  critical: 'var(--mantine-color-red-6)',
  warning: 'var(--mantine-color-yellow-7)',
  info: 'var(--app-text-secondary)',
};

interface ServerHealthIconsProps {
  server: McpServer;
  onReviewDrift?: (server: McpServer) => void;
  onReviewUpdate?: (server: McpServer) => void;
}

export const ServerHealthIcons: FC<ServerHealthIconsProps> = ({ server, onReviewDrift, onReviewUpdate }) => {
  const signals = serverHealthSignals(server);
  if (signals.length === 0) return null;

  return (
    <Group gap={4} wrap="nowrap">
      {signals.map((signal) => {
        const Icon = ICON[signal.kind];
        // Label and detail both go in the tooltip: colour alone never carries
        // the meaning, and the label is what a screen reader announces.
        const description = `${signal.label}. ${signal.detail}`;
        const action = signal.kind === 'drift' ? onReviewDrift : signal.kind === 'update' ? onReviewUpdate : undefined;
        const interactive = !!action;

        // Drift is actionable, so it is a real button — keyboard-reachable and
        // focus-ringed by the design system. The rest are statements of fact and
        // stay non-interactive rather than faking affordance.
        if (interactive) {
          return (
            <Tooltip key={signal.kind} label={description} multiline w={280} withArrow>
              <ActionIcon
                variant="subtle"
                color={signal.level === 'critical' ? 'red' : 'gray'}
                size="sm"
                aria-label={description}
                onClick={() => action?.(server)}
                style={{ flexShrink: 0 }}
              >
                <Icon size={15} />
              </ActionIcon>
            </Tooltip>
          );
        }

        return (
          <Tooltip key={signal.kind} label={description} multiline w={280} withArrow>
            <Icon
              size={15}
              color={COLOR[signal.level]}
              role="img"
              aria-label={description}
              style={{ flexShrink: 0, cursor: 'help' }}
            />
          </Tooltip>
        );
      })}
    </Group>
  );
};
