import '@testing-library/jest-dom/vitest';

import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { ContributionHeatmap } from './ContributionHeatmap';
import { intensityLevel } from './contributionHeatmapUtils';

function localISODate(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isoDaysAgo(n: number): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - n);
  return localISODate(d);
}

describe('ContributionHeatmap', () => {
  it('maps counts to the expected intensity buckets', () => {
    expect(intensityLevel(0)).toBe(0);
    expect(intensityLevel(1)).toBe(1);
    expect(intensityLevel(2)).toBe(1);
    expect(intensityLevel(4)).toBe(2);
    expect(intensityLevel(8)).toBe(3);
    expect(intensityLevel(20)).toBe(4);
    expect(intensityLevel(Number.NaN)).toBe(0);
  });

  it('renders a full gap-filled grid (whole weeks) even when days is empty', () => {
    renderPage(<ContributionHeatmap days={[]} weeks={10} />);
    const cells = screen.getAllByTestId('heatmap-cell');
    expect(cells).toHaveLength(70);
    expect(cells.every((c) => c.getAttribute('data-level') === '0')).toBe(true);
    expect(screen.getByText('0 sessions · 10 weeks')).toBeInTheDocument();
  });

  it('colours a seeded recent day with a non-zero level and zero for the rest', () => {
    const today = isoDaysAgo(0);
    renderPage(<ContributionHeatmap days={[{ date: today, count: 12 }]} weeks={8} />);

    const cells = screen.getAllByTestId('heatmap-cell');
    const seeded = cells.find((c) => c.getAttribute('data-date') === today);
    expect(seeded).toBeDefined();
    expect(seeded?.getAttribute('data-level')).toBe('4');
    expect(seeded?.getAttribute('data-count')).toBe('12');

    // At least one zero-level cell exists.
    expect(cells.some((c) => c.getAttribute('data-level') === '0')).toBe(true);
  });

  it('shows the total sessions summary for the visible window', () => {
    renderPage(
      <ContributionHeatmap
        days={[
          { date: isoDaysAgo(1), count: 3 },
          { date: isoDaysAgo(2), count: 5 },
        ]}
        weeks={6}
      />,
    );
    expect(screen.getByText('8 sessions · 6 weeks')).toBeInTheDocument();
  });

  it('aggregates duplicate dates and totals only visible grid cells', () => {
    const today = isoDaysAgo(0);
    renderPage(
      <ContributionHeatmap
        days={[
          { date: today, count: 2 },
          { date: today, count: 3 },
          { date: '2019-01-01', count: 100 },
        ]}
        weeks={8}
      />,
    );

    const seeded = screen.getAllByTestId('heatmap-cell').find((c) => c.getAttribute('data-date') === today);
    expect(seeded?.getAttribute('data-count')).toBe('5');
    expect(screen.getByText('5 sessions · 8 weeks')).toBeInTheDocument();
  });
});
