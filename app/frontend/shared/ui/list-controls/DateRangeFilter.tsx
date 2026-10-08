import { DatePickerInput, type DatePickerPreset, type DatesRangeValue } from '@mantine/dates';
import dayjs from 'dayjs';
import { useEffect, useState } from 'react';

interface DateRangeFilterProps {
  /** Inclusive ISO dates (YYYY-MM-DD); both unset means any date. */
  from?: string;
  until?: string;
  onChange: (from: string | undefined, until: string | undefined) => void;
}

function lastDays(days: number): [string, string] {
  const today = dayjs();
  return [today.subtract(days - 1, 'day').format('YYYY-MM-DD'), today.format('YYYY-MM-DD')];
}

const PRESETS: DatePickerPreset<'range'>[] = [
  { value: lastDays(1), label: 'Today' },
  { value: lastDays(7), label: 'Last 7 days' },
  { value: lastDays(14), label: 'Last 14 days' },
  { value: lastDays(30), label: 'Last 30 days' },
  { value: lastDays(90), label: 'Last 90 days' },
];

/**
 * The list's date filter. The list moves once a range has both ends (or is
 * cleared) — the first click of a range only marks its start.
 */
export function DateRangeFilter({ from, until, onChange }: DateRangeFilterProps) {
  const [range, setRange] = useState<DatesRangeValue<string>>([from ?? null, until ?? null]);

  useEffect(() => {
    setRange([from ?? null, until ?? null]);
  }, [from, until]);

  return (
    <DatePickerInput
      type="range"
      aria-label="Filter by date"
      placeholder="Any date"
      value={range}
      onChange={(next) => {
        setRange(next);
        const [start, end] = next;
        if (start && end) onChange(start, end);
        else if (!start && !end) onChange(undefined, undefined);
      }}
      presets={PRESETS}
      allowSingleDateInRange
      clearable
      maxDate={dayjs().format('YYYY-MM-DD')}
      valueFormat="MMM D"
      w={190}
    />
  );
}
