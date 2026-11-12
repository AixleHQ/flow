import { useEffect, useId, useRef, useState, type ReactNode } from 'react';

import classes from './Dashboard.module.css';
import { hasAccountFilters, NO_BILLING_METHOD, NO_FILTERS, type BillingMethodChoice, type Filters } from './filters';
import { ACCOUNT_STATUS_LABELS, ACCOUNT_TYPE_LABELS, BILLING_METHOD_LABELS } from './format';
import type { AccountStatus, AccountType, BillingMethod } from './types';

interface Option<T extends string> {
  value: T;
  label: string;
}

const STATUSES = (Object.keys(ACCOUNT_STATUS_LABELS) as AccountStatus[]).map((value) => ({
  value,
  label: ACCOUNT_STATUS_LABELS[value].label,
}));
const TYPES = (Object.keys(ACCOUNT_TYPE_LABELS) as AccountType[]).map((value) => ({
  value,
  label: ACCOUNT_TYPE_LABELS[value],
}));
const METHODS: Option<BillingMethodChoice>[] = [
  ...(Object.keys(BILLING_METHOD_LABELS) as BillingMethod[]).map((value) => ({
    value,
    label: BILLING_METHOD_LABELS[value],
  })),
  { value: NO_BILLING_METHOD, label: 'No billing method' },
];

const longDay = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
const formatDay = (day: string) => longDay.format(new Date(`${day}T00:00:00Z`));

const toggled = <T,>(list: T[], value: T) =>
  list.includes(value) ? list.filter((item) => item !== value) : [...list, value];

function choiceSummary<T extends string>(options: Option<T>[], chosen: T[]) {
  if (chosen.length > 1) return `${chosen.length} selected`;
  return options.find((option) => option.value === chosen[0])?.label ?? null;
}

function createdSummary({ createdFrom, createdTo }: Filters) {
  const [from, to] =
    createdFrom && createdTo && createdFrom > createdTo ? [createdTo, createdFrom] : [createdFrom, createdTo];
  if (from && to) return `${formatDay(from)} – ${formatDay(to)}`;
  if (from) return `from ${formatDay(from)}`;
  if (to) return `to ${formatDay(to)}`;
  return null;
}

interface MenuProps {
  label: string;
  summary: string | null;
  children: ReactNode;
}

/** A filter folded into a button; it opens under it and folds again on a click outside or Escape. */
function FilterMenu({ label, summary, children }: MenuProps) {
  const [open, setOpen] = useState(false);
  const wrapper = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const popoverId = useId();

  useEffect(() => {
    if (!open) return undefined;
    const closeOutside = (event: MouseEvent) => {
      if (!wrapper.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      setOpen(false);
      button.current?.focus();
    };
    document.addEventListener('mousedown', closeOutside);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('mousedown', closeOutside);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [open]);

  return (
    <div ref={wrapper} className={classes.filterMenu}>
      <button
        ref={button}
        type="button"
        className={`${classes.filterButton} ${summary ? classes.filterSet : ''}`}
        aria-expanded={open}
        aria-controls={popoverId}
        onClick={() => setOpen((was) => !was)}
      >
        {label}
        {summary && `: ${summary}`}
        <svg aria-hidden="true" className={classes.chevron} width="10" height="10" viewBox="0 0 10 10">
          <path
            d="M2 3.5 5 6.5 8 3.5"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>
      {open && (
        <div id={popoverId} className={classes.filterPopover}>
          {children}
        </div>
      )}
    </div>
  );
}

interface ChoicesProps<T extends string> {
  label: string;
  options: Option<T>[];
  chosen: T[];
  onChange: (chosen: T[]) => void;
}

function Choices<T extends string>({ label, options, chosen, onChange }: ChoicesProps<T>) {
  return (
    <FilterMenu label={label} summary={choiceSummary(options, chosen)}>
      <fieldset className={classes.filterGroup}>
        <legend className={classes.visuallyHidden}>{label}</legend>
        {options.map((option) => (
          <label key={option.value} className={classes.choice}>
            <input
              type="checkbox"
              checked={chosen.includes(option.value)}
              onChange={() => onChange(toggled(chosen, option.value))}
            />
            {option.label}
          </label>
        ))}
      </fieldset>
    </FilterMenu>
  );
}

interface Props {
  filters: Filters;
  today: string;
  onChange: (filters: Filters) => void;
}

export default function FilterBar({ filters, today, onChange }: Props) {
  return (
    <div role="group" aria-label="Filters" className={classes.filterBar}>
      <Choices
        label="Account status"
        options={STATUSES}
        chosen={filters.statuses}
        onChange={(statuses) => onChange({ ...filters, statuses })}
      />
      <Choices
        label="Account type"
        options={TYPES}
        chosen={filters.types}
        onChange={(types) => onChange({ ...filters, types })}
      />
      <Choices
        label="Billing method"
        options={METHODS}
        chosen={filters.methods}
        onChange={(methods) => onChange({ ...filters, methods })}
      />
      <FilterMenu label="Account created" summary={createdSummary(filters)}>
        <fieldset className={classes.filterGroup}>
          <legend className={classes.visuallyHidden}>Account created</legend>
          <label className={classes.field}>
            From
            <input
              type="date"
              aria-label="Created from"
              value={filters.createdFrom}
              max={today}
              onChange={(event) => onChange({ ...filters, createdFrom: event.target.value })}
            />
          </label>
          <label className={classes.field}>
            To
            <input
              type="date"
              aria-label="Created to"
              value={filters.createdTo}
              max={today}
              onChange={(event) => onChange({ ...filters, createdTo: event.target.value })}
            />
          </label>
        </fieldset>
      </FilterMenu>
      {hasAccountFilters(filters) && (
        <button
          type="button"
          className={classes.clearFilters}
          onClick={() => onChange({ ...NO_FILTERS, query: filters.query })}
        >
          Clear filters
        </button>
      )}
    </div>
  );
}
