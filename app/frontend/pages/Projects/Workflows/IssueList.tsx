import { Button } from '@mantine/core';
import { IconAlertCircle, IconAlertTriangle } from '@tabler/icons-react';

import classes from './BuilderPage.module.css';
import type { IssueFix, WorkflowIssue } from './dataFlow';

interface IssueListProps {
  issues: WorkflowIssue[];
  /** The label of a fix button, or null to offer none (read-only, or nothing it could act on). */
  fixLabel: (fix: IssueFix) => string | null;
  onFix: (fix: IssueFix) => void;
  label: string;
}

/** Data-flow problems for one part of a session, errors first, each with its one-click fix. */
export function IssueList({ issues, fixLabel, onFix, label }: IssueListProps) {
  if (issues.length === 0) return null;
  const ordered = [...issues.filter((i) => i.severity === 'error'), ...issues.filter((i) => i.severity !== 'error')];

  return (
    <ul className={classes.issueList} aria-label={label}>
      {ordered.map((issue, index) => {
        const { fix } = issue;
        const action = fix ? fixLabel(fix) : null;
        const isError = issue.severity === 'error';
        return (
          <li key={`${issue.code}-${index}`} className={isError ? classes.issueError : classes.issueWarning}>
            {isError ? (
              <IconAlertCircle size={14} className={classes.issueIcon} aria-label="Error" />
            ) : (
              <IconAlertTriangle size={14} className={classes.issueIcon} aria-label="Warning" />
            )}
            <span className={classes.issueMessage}>{issue.message}</span>
            {fix && action && (
              <Button size="compact-xs" variant="light" color={isError ? 'red' : 'yellow'} onClick={() => onFix(fix)}>
                {action}
              </Button>
            )}
          </li>
        );
      })}
    </ul>
  );
}
