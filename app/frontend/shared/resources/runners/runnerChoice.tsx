import { Link } from '@inertiajs/react';
import { Anchor, Select, Text } from '@mantine/core';

import type { RunnerSummary } from '@/types/generated';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import { companyProjectRunnerPath } from 'shared/routes';
import { StatusTag } from 'shared/ui/sessions';

import { humanize } from './runnerConfig';
import { runnerTypeTitle } from './runnerCopy';

const HOSTED = 'hosted';

const optionLabel = (runner: RunnerSummary) =>
  `${runner.name} · ${runner.deleted ? 'Deleted' : humanize(runner.status)}`;

interface RunnerSelectProps {
  label: string;
  hostedLabel: string;
  runners: RunnerSummary[];
  value: number | null;
  onChange: (runnerId: number | null) => void;
  disabled?: boolean;
  /** Interactive sessions cannot run on a runner until the tunnel exists (§8), so those options are off. */
  interactive?: boolean;
  description?: string;
}

/**
 * `Hosted` plus the runners the project can see, each with its status. A runner the value names but
 * the list does not hold (no longer visible) still shows, by id, so the choice is never silently
 * read as hosted.
 */
export function RunnerSelect({
  label,
  hostedLabel,
  runners,
  value,
  onChange,
  disabled,
  interactive = false,
  description,
}: RunnerSelectProps) {
  const listed = runners.some((runner) => runner.id === value);
  const data = [
    { value: HOSTED, label: hostedLabel },
    ...runners.map((runner) => ({
      value: String(runner.id),
      label: interactive ? `${optionLabel(runner)} · can't run interactive sessions yet` : optionLabel(runner),
      disabled: interactive || (runner.deleted && runner.id !== value),
    })),
    ...(value != null && !listed ? [{ value: String(value), label: `Runner #${value}`, disabled: true }] : []),
  ];

  return (
    <Select
      label={label}
      description={description}
      data={data}
      value={value == null ? HOSTED : String(value)}
      onChange={(next) => onChange(next == null || next === HOSTED ? null : Number(next))}
      allowDeselect={false}
      disabled={disabled}
    />
  );
}

/** The §11 disclosure: where the launching user's agent login goes. */
export function RunnerCredentialNote({ runner }: { runner: RunnerSummary | undefined }) {
  if (!runner) return null;

  return (
    <Text size="xs" c="dimmed" mt={4}>
      Your agent login is used on this runner, which is operated by <em>{runner.operatedBy}</em>.
    </Text>
  );
}

/** "Runs on": `Hosted`, or the runner's name and type, linking to the runner. Renders nothing without the flag. */
export function RunsOnBadge({ runner, projectId }: { runner: RunnerSummary | null | undefined; projectId: number }) {
  const externalRunners = useFeatureFlag('externalRunners');
  if (!externalRunners) return null;
  if (!runner) return <StatusTag plain>Hosted</StatusTag>;

  const label = `${runner.name} · ${runnerTypeTitle(runner.runnerType)}`;
  // A deleted runner has no page left to open.
  if (runner.deleted) return <StatusTag plain>{label}</StatusTag>;

  return (
    <Anchor component={Link} href={companyProjectRunnerPath(projectId, runner.id)} underline="hover">
      <StatusTag plain>{label}</StatusTag>
    </Anchor>
  );
}

