import classes from './TabBar.module.css';

interface TabDef<T extends string> {
  value: T;
  label: string;
  /** Rendered small and mono after the label, e.g. the asset count. */
  count?: number;
  disabled?: boolean;
}

interface TabBarProps<T extends string> {
  tabs: TabDef<T>[];
  value: T;
  onChange: (value: T) => void;
  /** Render inside a DetailHeader rather than as a standalone strip. */
  inline?: boolean;
  'aria-label': string;
}

/**
 * The run-detail / running-run tab strip. Two tab systems used to coexist with
 * separately scoped handlers; this is the only one now, and callers keep their
 * own state.
 */
export function TabBar<T extends string>({ tabs, value, onChange, inline = false, ...rest }: TabBarProps<T>) {
  return (
    <div
      className={inline ? `${classes.bar} ${classes.inline}` : classes.bar}
      role="tablist"
      aria-label={rest['aria-label']}
    >
      {tabs.map((tab) => (
        <button
          key={tab.value}
          type="button"
          role="tab"
          aria-selected={tab.value === value}
          disabled={tab.disabled}
          className={tab.value === value ? `${classes.tab} ${classes.active}` : classes.tab}
          onClick={() => onChange(tab.value)}
        >
          {tab.label}
          {tab.count != null && <span className={classes.count}>{tab.count}</span>}
        </button>
      ))}
    </div>
  );
}
