import { Box, Group, Text, Tooltip } from '@mantine/core';
import { useMemo } from 'react';

export interface HeatmapDay {
  date: string; // ISO yyyy-mm-dd
  count: number;
}

interface ContributionHeatmapProps {
  days: HeatmapDay[];
  weeks?: number;
}

// Five GitHub-like intensity buckets. Level 0 uses a subtle theme surface; 1–4 ramp green.
const LEVEL_COLORS = ['var(--app-bg-elevated)', '#0e4429', '#006d32', '#26a641', '#39d353'];

export function intensityLevel(count: number): number {
  if (count <= 0) return 0;
  if (count <= 2) return 1;
  if (count <= 5) return 2;
  if (count <= 9) return 3;
  return 4;
}

function toISODate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * Dependency-free GitHub-style contribution calendar. Renders `weeks` columns of 7
 * day-cells, coloured by an intensity bucket derived from each day's session count.
 * Gap-fills internally: builds the full date range and defaults missing days to 0, so
 * an empty `days` prop still renders a complete grid.
 */
export function ContributionHeatmap({ days, weeks = 53 }: ContributionHeatmapProps) {
  const columns = useMemo(() => {
    const byDate = new Map<string, number>();
    for (const d of days) byDate.set(d.date, d.count);

    // End on the most recent Saturday-aligned week that contains today.
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    // Roll back to the start of the window: weeks*7 days, aligned to week start (Sunday).
    const end = new Date(today);
    const start = new Date(today);
    start.setDate(start.getDate() - (weeks * 7 - 1));
    // Align start to a Sunday so columns are clean weeks.
    start.setDate(start.getDate() - start.getDay());

    const cols: { date: string; count: number; level: number }[][] = [];
    const cursor = new Date(start);
    while (cursor <= end) {
      const week: { date: string; count: number; level: number }[] = [];
      for (let i = 0; i < 7; i++) {
        const iso = toISODate(cursor);
        const count = byDate.get(iso) ?? 0;
        week.push({ date: iso, count, level: intensityLevel(count) });
        cursor.setDate(cursor.getDate() + 1);
      }
      cols.push(week);
    }
    return cols;
  }, [days, weeks]);

  const total = useMemo(() => days.reduce((sum, d) => sum + d.count, 0), [days]);

  return (
    <Box>
      <Group justify="space-between" mb="xs">
        <Text size="sm" fw={600}>
          Activity
        </Text>
        <Text size="xs" c="dimmed">
          {total.toLocaleString()} sessions in the last year
        </Text>
      </Group>
      <Box style={{ overflowX: 'auto' }}>
        <Box style={{ display: 'flex', gap: 3 }} data-testid="contribution-heatmap">
          {columns.map((week, wi) => (
            <Box key={wi} style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              {week.map((cell) => (
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
                      backgroundColor: LEVEL_COLORS[cell.level],
                    }}
                  />
                </Tooltip>
              ))}
            </Box>
          ))}
        </Box>
      </Box>
    </Box>
  );
}

export default ContributionHeatmap;
