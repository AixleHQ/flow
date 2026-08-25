import { Box, Group, Text, Tooltip } from '@mantine/core';
import { useMemo } from 'react';

import { intensityLevel } from './contributionHeatmapUtils';

interface HeatmapDay {
  date: string; // ISO yyyy-mm-dd
  count: number;
}

interface ContributionHeatmapProps {
  days: HeatmapDay[];
  weeks?: number;
}

// Terracotta ramp: empty cell token + accent opacity steps + peak accent.
const LEVEL_COLORS = [
  'var(--heatmap-cell-empty)',
  'rgba(207,107,74,0.25)',
  'rgba(207,107,74,0.5)',
  'rgba(207,107,74,0.75)',
  'var(--app-accent)',
];

function toISODate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function periodLabel(weeks: number): string {
  if (weeks >= 52) return 'last year';
  if (weeks === 1) return '1 week';
  return `${weeks} weeks`;
}

/**
 * Dependency-free GitHub-style contribution calendar. Renders `weeks` columns of 7
 * day-cells, coloured by an intensity bucket derived from each day's session count.
 * Gap-fills internally: builds the full date range and defaults missing days to 0, so
 * an empty `days` prop still renders a complete grid.
 */
export function ContributionHeatmap({ days, weeks = 53 }: ContributionHeatmapProps) {
  const { rows, total } = useMemo(() => {
    const byDate = new Map<string, number>();
    for (const d of days) {
      const count = Number.isFinite(d.count) ? d.count : 0;
      byDate.set(d.date, (byDate.get(d.date) ?? 0) + count);
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const endSunday = new Date(today);
    endSunday.setDate(endSunday.getDate() - endSunday.getDay());
    const startSunday = new Date(endSunday);
    startSunday.setDate(startSunday.getDate() - (weeks - 1) * 7);

    const weekColumns: { date: string; count: number; level: number }[][] = [];
    for (let w = 0; w < weeks; w++) {
      const week: { date: string; count: number; level: number }[] = [];
      for (let d = 0; d < 7; d++) {
        const cursor = new Date(startSunday);
        cursor.setDate(cursor.getDate() + w * 7 + d);
        const iso = toISODate(cursor);
        const count = byDate.get(iso) ?? 0;
        week.push({ date: iso, count, level: intensityLevel(count) });
      }
      weekColumns.push(week);
    }

    // Reference lays out 7 day-rows × N week-columns (GitHub-style).
    const gridRows = Array.from({ length: 7 }, (_, dayIndex) => weekColumns.map((week) => week[dayIndex]!));
    const visibleTotal = gridRows.flat().reduce((sum, cell) => sum + cell.count, 0);
    return { rows: gridRows, total: visibleTotal };
  }, [days, weeks]);

  const windowLabel = periodLabel(weeks);

  return (
    <Box>
      <Group justify="space-between" mb={16} align="center">
        <Text fw={600} style={{ fontSize: 13, letterSpacing: '-0.01em' }}>
          Session activity
        </Text>
        <Text
          c="var(--app-text-secondary)"
          fw={600}
          tt="uppercase"
          style={{
            fontSize: 10,
            letterSpacing: '0.05em',
            padding: '2px 8px',
            borderRadius: 4,
            border: '1px solid var(--app-border-default)',
            backgroundColor: 'var(--app-bg-hover)',
          }}
        >
          {total.toLocaleString()} sessions · {windowLabel}
        </Text>
      </Group>
      <Box style={{ overflowX: 'auto' }}>
        <Box style={{ display: 'flex', flexDirection: 'column', gap: 3 }} data-testid="contribution-heatmap">
          {rows.map((row, ri) => (
            <Box key={ri} style={{ display: 'flex', gap: 3 }}>
              {row.map((cell) => (
                <Tooltip key={cell.date} label={`${cell.count} sessions on ${cell.date}`} withArrow>
                  <Box
                    data-testid="heatmap-cell"
                    data-level={cell.level}
                    data-date={cell.date}
                    data-count={cell.count}
                    style={{
                      width: 11,
                      height: 11,
                      borderRadius: 2,
                      backgroundColor: LEVEL_COLORS[cell.level] ?? LEVEL_COLORS[0],
                    }}
                  />
                </Tooltip>
              ))}
            </Box>
          ))}
        </Box>
      </Box>
      <Group justify="flex-end" gap={6} mt={12}>
        <Text c="var(--app-text-tertiary)" style={{ fontSize: 11 }}>
          Less
        </Text>
        {LEVEL_COLORS.map((color, level) => (
          <Box key={level} w={11} h={11} style={{ borderRadius: 2, backgroundColor: color }} />
        ))}
        <Text c="var(--app-text-tertiary)" style={{ fontSize: 11 }}>
          More
        </Text>
      </Group>
    </Box>
  );
}
