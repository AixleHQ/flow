import '@testing-library/jest-dom/vitest';

import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { ContributionHeatmap, intensityLevel } from './ContributionHeatmap';

function isoDaysAgo(n: number): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

describe('ContributionHeatmap', () => {
  it('maps counts to the expected intensity buckets', () => {
    expect(intensityLevel(0)).toBe(0);
    expect(intensityLevel(1)).toBe(1);
    expect(intensityLevel(2)).toBe(1);
    expect(intensityLevel(4)).toBe(2);
    expect(intensityLevel(8)).toBe(3);
    expect(intensityLevel(20)).toBe(4);
  });

  it('renders a full gap-filled grid (whole weeks) even when days is empty', () => {
    renderPage(<ContributionHeatmap days={[]} weeks={10} />);
    const cells = screen.getAllByTestId('heatmap-cell');
    // At least weeks*7 cells, always a whole number of 7-day columns.
    expect(cells.length).toBeGreaterThanOrEqual(70);
    expect(cells.length % 7).toBe(0);
    // Empty series → every cell is level 0.
    expect(cells.every((c) => c.getAttribute('data-level') === '0')).toBe(true);
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

  it('shows the total sessions summary', () => {
    renderPage(
      <ContributionHeatmap
        days={[
          { date: isoDaysAgo(1), count: 3 },
          { date: isoDaysAgo(2), count: 5 },
        ]}
        weeks={6}
      />,
    );
    expect(screen.getByText('8 sessions in the last year')).toBeInTheDocument();
  });
});
