import { Link } from '@inertiajs/react';
import { Switch } from '@mantine/core';
import {
  IconBolt,
  IconBrandSlack,
  IconBrandTeams,
  IconClock,
  IconColumns,
  IconMessage,
  IconPencil,
  IconPlus,
  IconTicket,
  IconTrash,
  IconUser,
  IconWebhook,
} from '@tabler/icons-react';

import { creatorLabel, creatorTone, triggerMeta, triggerSource, triggerTitle } from './describeTrigger';
import type { TrackerOption } from './trackerTrigger';
import type { ChatProviderOption, Trigger } from './types';

const CHAT_ICONS: Record<string, typeof IconBolt> = {
  slack: IconBrandSlack,
  teams: IconBrandTeams,
};

const SOURCE_ICONS: Record<string, typeof IconBolt> = {
  board: IconColumns,
  schedule: IconClock,
  chat: IconMessage,
  webhook: IconWebhook,
  tracker: IconTicket,
};

const SOURCE_BADGES: Record<string, string> = {
  board: 'BOARD.COLUMN_CHANGED',
  schedule: 'SCHEDULE.CRON',
  webhook: 'WEBHOOK.RECEIVED',
};

const iconButton = {
  background: 'none',
  border: 'none',
  cursor: 'pointer',
  color: 'var(--app-text-tertiary)',
  padding: 6,
  borderRadius: 4,
  display: 'flex',
  transition: 'all 0.12s',
} as const;

interface TriggerCardsProps {
  triggers: Trigger[];
  trackers?: TrackerOption[];
  chatProviders?: ChatProviderOption[];
  readOnly: boolean;
  onEdit: (t: Trigger) => void;
  onDelete: (t: Trigger) => void;
  onToggle: (t: Trigger, enabled: boolean) => void;
  // Shown on the project's Triggers page, where cards of several workflows sit together.
  workflowHref?: (t: Trigger) => string | null;
  onAdd?: () => void;
}

export function TriggerCards({
  triggers,
  trackers = [],
  chatProviders = [],
  readOnly,
  onEdit,
  onDelete,
  onToggle,
  workflowHref,
  onAdd,
}: TriggerCardsProps) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 10 }}>
      {triggers.map((t) => {
        const source = triggerSource(t);
        const Icon =
          (source === 'chat' ? CHAT_ICONS[t.chat_provider ?? 'slack'] : null) ?? SOURCE_ICONS[source] ?? IconBolt;
        const isDisabled = t.enabled === false;
        const href = workflowHref?.(t);
        const title = triggerTitle(t);
        return (
          <article
            key={`${t.kind}-${t.id}`}
            aria-label={title}
            style={{
              display: 'flex',
              flexDirection: 'column',
              gap: 10,
              padding: '14px 16px',
              background: 'var(--app-bg-paper)',
              border: '1px solid var(--app-border-default)',
              borderRadius: 8,
              opacity: isDisabled ? 0.55 : 1,
              transition: 'opacity 0.15s, border-color 0.15s',
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <div
                style={{
                  width: 32,
                  height: 32,
                  borderRadius: 8,
                  background: 'var(--app-bg-paper)',
                  border: '1px solid var(--app-border-default)',
                  color: 'var(--app-text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0,
                }}
              >
                <Icon size={16} />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: 14,
                    fontWeight: 600,
                    color: 'var(--app-text-primary)',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {title}
                </div>
                <div
                  style={{
                    fontSize: 12,
                    color: 'var(--app-text-secondary)',
                    marginTop: 2,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {triggerMeta(t, trackers, chatProviders)}
                </div>
              </div>
            </div>

            {href && (
              <div style={{ fontSize: 12, color: 'var(--app-text-secondary)', minWidth: 0 }}>
                Starts{' '}
                <Link href={href} style={{ color: 'var(--app-primary-strong)' }}>
                  {t.workflow_name ?? 'workflow'}
                </Link>
              </div>
            )}

            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                fontSize: 12,
                color: creatorTone(t),
                minWidth: 0,
              }}
            >
              <IconUser size={13} style={{ flexShrink: 0 }} />
              {/* The card is narrow enough to clip the longer labels — keep the full text reachable. */}
              <span
                title={creatorLabel(t)}
                style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}
              >
                {creatorLabel(t)}
              </span>
            </div>

            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: 8,
                marginTop: 'auto',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0, flexWrap: 'wrap' }}>
                <span
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    letterSpacing: '0.04em',
                    color: 'var(--app-text-tertiary)',
                    background: 'var(--app-bg-paper)',
                    border: '1px solid var(--app-border-default)',
                    padding: '2px 8px',
                    borderRadius: 4,
                    textTransform: 'uppercase',
                    flexShrink: 0,
                  }}
                >
                  {source === 'chat'
                    ? `${(t.chat_provider ?? 'slack').toUpperCase()}.MESSAGE`
                    : (SOURCE_BADGES[source] ?? t.event_type)}
                </span>
              </div>

              {!readOnly && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                  {/* A board-column trigger has no off switch: removing it is how it stops. */}
                  {source !== 'board' && (
                    <>
                      <Switch
                        size="xs"
                        aria-label={`Enable ${title}`}
                        checked={t.enabled !== false}
                        onChange={(e) => onToggle(t, e.currentTarget.checked)}
                      />
                      <div style={{ width: 1, height: 16, background: 'var(--app-border-default)', margin: '0 4px' }} />
                    </>
                  )}
                  <button aria-label={`Edit ${title}`} onClick={() => onEdit(t)} style={iconButton}>
                    <IconPencil size={14} />
                  </button>
                  <button aria-label={`Delete ${title}`} onClick={() => onDelete(t)} style={iconButton}>
                    <IconTrash size={14} />
                  </button>
                </div>
              )}
            </div>
          </article>
        );
      })}

      {!readOnly && onAdd && (
        <button
          onClick={onAdd}
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 8,
            minHeight: 96,
            border: '1px dashed var(--app-border-default)',
            borderRadius: 8,
            color: 'var(--app-text-secondary)',
            fontSize: 13,
            fontWeight: 500,
            cursor: 'pointer',
            background: 'none',
            fontFamily: 'inherit',
          }}
        >
          <IconPlus size={16} />
          Add a trigger
        </button>
      )}
    </div>
  );
}
