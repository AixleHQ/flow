import { Group, Select } from '@mantine/core';
import { DatePickerInput, type DatesRangeValue } from '@mantine/dates';
import dayjs from 'dayjs';
import { useEffect, useState } from 'react';

import { PERIOD_OPTIONS, type Period, type PeriodWindow } from './chartHelpers';

interface PeriodFilterProps extends PeriodWindow {
  onChange: (next: PeriodWindow) => void;
  /** Accessible name of the preset select; pages with more than one picker tell them apart. */
  label?: string;
}

/**
 * A preset period, or "Custom range" with two calendar days. Choosing Custom only
 * opens the date picker — the page moves once both ends are picked, so a half-picked
 * range never reloads the charts.
 */
export function PeriodFilter({ period, from, to, onChange, label = 'Period' }: PeriodFilterProps) {
  const [custom, setCustom] = useState(period === 'custom');
  const [range, setRange] = useState<DatesRangeValue<string>>([from, to]);

  useEffect(() => {
    setCustom(period === 'custom');
    setRange([from, to]);
  }, [period, from, to]);

  return (
    <Group gap="sm" wrap="nowrap">
      <Select
        aria-label={label}
        value={custom ? 'custom' : period}
        onChange={(value) => {
          if (value === 'custom') {
            setCustom(true);
            return;
          }
          setCustom(false);
          onChange({ period: (value ?? '30d') as Period, from, to });
        }}
        data={PERIOD_OPTIONS}
        allowDeselect={false}
        size="sm"
        w={150}
      />
      {custom && (
        <DatePickerInput
          type="range"
          aria-label="Custom date range"
          placeholder="Pick dates"
          value={range}
          onChange={(next) => {
            setRange(next);
            const [start, end] = next;
            if (start && end) onChange({ period: 'custom', from: start, to: end });
          }}
          allowSingleDateInRange
          maxDate={dayjs().format('YYYY-MM-DD')}
          valueFormat="MMM D, YYYY"
          size="sm"
          w={240}
        />
      )}
    </Group>
  );
}
