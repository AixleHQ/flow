import { Box, Paper, Skeleton, Text } from '@mantine/core';
import { type CSSProperties, type ReactNode } from 'react';

import { LOGO_TILE_BG } from 'shared/theme/vendorColors';
import claudeLogo from 'shared/ui/agent-logos/claude.png';
import codexLogo from 'shared/ui/agent-logos/codex.png';
import cursorLogo from 'shared/ui/agent-logos/cursor.png';
import geminiLogo from 'shared/ui/agent-logos/gemini.png';

export type Period = '7d' | '30d' | '90d' | '1y';

export interface AgentSessionCount {
  agentType: string;
  sessions: number;
  costCents: number;
  tokens: number;
}
export interface AgentActivityPoint {
  date: string;
  agentType: string;
  sessions: number;
}
export interface AgentActivityData {
  agentTypes: string[];
  sessionsByAgent: AgentSessionCount[];
  activityOverTime: AgentActivityPoint[];
}

// Warm chart-series palette. Primary = accent; everything else is a warm neutral ramp.
// Identity on agent charts is carried by logo + label; color is a secondary cue.
// Falls back to the always-defined semantic token when `--accent` hasn't been set by
// the current page (it's only ever defined by the Workflow Builder's stylesheet).
export const CHART_ACCENT = 'var(--accent, var(--app-primary))';
export const CHART_TAUPE = 'var(--app-chart-warm-1)';
export const CHART_NEUTRAL = 'var(--app-text-tertiary)';

const AGENT_COLOR: Record<string, string> = {
  claude_code: CHART_ACCENT,
  cursor: 'var(--app-chart-warm-2)',
  cursor_cli: 'var(--app-chart-warm-2)',
  codex: 'var(--app-chart-warm-1)',
  gemini: 'var(--app-chart-warm-3)',
  gemini_cli: 'var(--app-chart-warm-3)',
  antigravity_cli: 'var(--app-chart-warm-3)',
  // No xAI artwork ships in this repo, so a Grok row renders the neutral chip
  // AgentLogo falls back to; naming it here keeps the runtime known, not unmapped.
  grok: CHART_NEUTRAL,
};

export const getAgentColor = (agentType: string): string => AGENT_COLOR[agentType] ?? CHART_NEUTRAL;

const AGENT_LOGO_SRC: Record<string, string> = {
  claude_code: claudeLogo,
  cursor: cursorLogo,
  cursor_cli: cursorLogo,
  codex: codexLogo,
  gemini: geminiLogo,
  gemini_cli: geminiLogo,
  antigravity_cli: geminiLogo,
};

function agentLogoChipStyle(agentType: string, size: number): CSSProperties {
  const base: CSSProperties = {
    width: size,
    height: size,
    borderRadius: 5,
    flexShrink: 0,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  };

  if (agentType === 'codex') {
    return { ...base, backgroundColor: LOGO_TILE_BG.light };
  }
  if (agentType === 'gemini' || agentType === 'gemini_cli' || agentType === 'antigravity_cli') {
    return { ...base, backgroundColor: LOGO_TILE_BG.dark, border: '1px solid var(--app-border-default)' };
  }
  return base;
}

function agentLogoImageSize(agentType: string, chipSize: number): number {
  if (agentType === 'codex') return Math.round(chipSize * (13 / 18));
  if (agentType === 'gemini' || agentType === 'gemini_cli' || agentType === 'antigravity_cli')
    return Math.round(chipSize * (12 / 18));
  return chipSize;
}

// Agent brand mark; falls back to a rounded color chip for unrecognized agent types.
export function AgentLogo({ agentType, size = 18 }: { agentType: string; size?: number }) {
  const src = AGENT_LOGO_SRC[agentType];
  if (src) {
    const imageSize = agentLogoImageSize(agentType, size);
    return (
      <Box data-testid="agent-logo" style={agentLogoChipStyle(agentType, size)}>
        <Box component="img" src={src} alt={agentType} w={imageSize} h={imageSize} style={{ objectFit: 'contain' }} />
      </Box>
    );
  }
  return (
    <Box
      data-testid="agent-logo"
      w={size}
      h={size}
      style={{ borderRadius: 5, backgroundColor: getAgentColor(agentType), flexShrink: 0 }}
    />
  );
}

// Small uppercase pill used to show the active data scope in a chart card's corner.
export function ScopeBadge({ children }: { children: ReactNode }) {
  return (
    <Text
      c="dimmed"
      fw={600}
      tt="uppercase"
      style={{
        fontSize: 10,
        letterSpacing: '0.05em',
        padding: '2px 8px',
        borderRadius: 4,
        border: '1px solid var(--app-border-default)',
        backgroundColor: 'var(--app-bg-elevated)',
      }}
    >
      {children}
    </Text>
  );
}

export const PERIOD_OPTIONS = [
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: '90d', label: 'Last 90 days' },
  { value: '1y', label: 'Last year' },
];

export const chartTooltipStyle = {
  backgroundColor: 'var(--app-bg-default)',
  border: '1px solid var(--app-border-default)',
  borderRadius: 8,
  fontSize: 12,
  color: 'var(--app-text-primary)',
};

// Scales down as the digit count grows so a future 6-7 digit total still fits the donut hole.
export function centerLabelFontSize(value: number): number {
  const digits = String(Math.trunc(value)).length;
  if (digits >= 7) return 12;
  if (digits >= 6) return 13;
  if (digits >= 5) return 15;
  return 18;
}

export function sharePct(count: number, total: number): number {
  return total > 0 ? Math.round((count / total) * 100) : 0;
}

export function tickIntervalForPeriod(period: Period): number {
  const days = period === '7d' ? 7 : period === '30d' ? 30 : period === '90d' ? 90 : 365;
  return days <= 7 ? 0 : days <= 30 ? 4 : days <= 90 ? 9 : 29;
}

export function formatAxisDate(iso: string | number | ReactNode): string {
  return new Date(String(iso)).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

export function SummarySkeletons() {
  return (
    <>
      {Array.from({ length: 5 }).map((_, i) => (
        <Paper key={i} withBorder px={20} py={18} radius="md" bg="var(--app-bg-card)">
          <Skeleton height={12} width={100} mb={12} />
          <Skeleton height={24} width={70} />
        </Paper>
      ))}
    </>
  );
}

export function ChartSkeleton({ height = 240 }: { height?: number }) {
  return <Skeleton height={height} radius="sm" />;
}

export function buildActivityChartData(data: AgentActivityData): Record<string, string | number>[] {
  // Group by the raw ISO date (unambiguously sortable) rather than the display label,
  // so the chart stays chronological regardless of the input array's row order.
  const dateMap = new Map<string, Record<string, string | number>>();
  for (const point of data.activityOverTime) {
    if (!dateMap.has(point.date)) dateMap.set(point.date, { date: point.date });
    dateMap.get(point.date)![point.agentType] = point.sessions;
  }
  // The backend only emits a (date, agentType) row when that agent had ≥1 session that
  // day, so most rows are missing most agent keys. Recharts treats a missing key as a
  // gap (not 0) and doesn't connect across it, which fragments each agent's line into
  // disconnected flat segments instead of a continuous trend. Zero-fill every known
  // agent type on every date that has data for *some* agent, so each line spans the
  // full visible range and actually dips to 0 on its quiet days.
  return Array.from(dateMap.keys())
    .sort()
    .map((iso) => {
      const row = dateMap.get(iso)!;
      const filled: Record<string, string | number> = { date: iso };
      for (const agentType of data.agentTypes) filled[agentType] = row[agentType] ?? 0;
      return { ...filled, date: new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) };
    });
}
