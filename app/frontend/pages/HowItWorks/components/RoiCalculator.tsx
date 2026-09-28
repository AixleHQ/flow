import { Badge, Box, Button, Group, NumberInput, type NumberInputProps, Stack, Text, Title } from '@mantine/core';
import { IconArrowRight } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import {
  calculateRoi,
  DEFAULT_ROI_INPUTS,
  formatMoney,
  formatMonths,
  formatPercent,
  HOURS_PER_QUEUE_MONTH,
  IRR_BENCHMARK,
  MAX_YEARS,
  monthlyCostPerQueue,
  type RoiInputs,
  suggestedQueues,
} from 'shared/lib/roi';
import { newWorkspacePath } from 'shared/routes';

import classes from './RoiCalculator.module.css';

interface RoiCalculatorProps {
  queueHourlyRate: number;
}

// NumberInputProps rather than ComponentProps: the component is generic over
// number | bigint, and ComponentProps resolves that to the constraint, widening
// every numeric prop to something nothing here uses.
type FieldProps = Omit<NumberInputProps, 'value' | 'onChange' | 'label'>;

const Row = ({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) => (
  <div className={`${classes.row} ${strong ? classes.rowStrong : ''}`}>
    <span className={classes.rowLabel}>{label}</span>
    <span className={classes.rowValue}>{value}</span>
  </div>
);

export const RoiCalculator = ({ queueHourlyRate }: RoiCalculatorProps) => {
  const [inputs, setInputs] = useState<RoiInputs>({ ...DEFAULT_ROI_INPUTS, queueHourlyRate });

  // Mantine hands back a string while the field is mid-edit (and for an empty
  // one). Everything downstream divides by these, so they are coerced here
  // rather than guarded in the model.
  const set = (key: keyof RoiInputs) => (value: number | string) =>
    setInputs((prev) => ({ ...prev, [key]: typeof value === 'number' ? value : Number(value) || 0 }));

  const roi = useMemo(() => calculateRoi(inputs), [inputs]);
  const queues = useMemo(() => suggestedQueues(inputs), [inputs]);
  const hourlyBill = queues * inputs.queueHourlyRate;

  const field = (label: string, key: keyof RoiInputs, props: FieldProps = {}) => (
    <NumberInput
      label={label}
      value={inputs[key]}
      onChange={set(key)}
      min={0}
      allowNegative={false}
      thousandSeparator=","
      {...props}
    />
  );

  return (
    <div className={classes.grid}>
      <div className={classes.panel}>
        <Stack gap="lg">
          <div>
            <Title order={3} fz="h4">
              Your numbers
            </Title>
            <Text size="sm" c="var(--app-text-secondary)" mt={4}>
              Start from one process you would hand over. Everything below updates as you type.
            </Text>
          </div>

          <Stack gap="md">
            {field('Labour hours this process costs you a year', 'hoursSavedPerYear', {
              description: 'Hours of people time the workflow takes off the team.',
              step: 100,
            })}
            {field('Fully loaded cost of an hour', 'laborCostPerHour', {
              description: 'Salary, taxes and overhead, divided by hours worked.',
              prefix: '$',
            })}
            {field('How many times faster Flow runs it', 'acceleratorMultiple', {
              description:
                'At 1× a queue-hour simply replaces an hour of labour. Raise it if agents working in parallel, overnight, get the work done sooner.',
              suffix: '×',
              min: 1,
            })}
            {field('One-off setup', 'setupCost', {
              description: 'Building and proving the workflows, once.',
              prefix: '$',
              step: 1000,
            })}
            {field('Years to look at', 'years', { min: 1, max: MAX_YEARS })}
          </Stack>

          <Text size="xs" c="var(--app-text-tertiary)">
            A queue is one session running at a time, priced at {formatMoney(inputs.queueHourlyRate, 2)} an hour for
            every hour it is open — {HOURS_PER_QUEUE_MONTH} hours a month, or{' '}
            {formatMoney(monthlyCostPerQueue(inputs.queueHourlyRate))} a queue.
          </Text>
        </Stack>
      </div>

      <section className={classes.result} aria-label="What your numbers come to">
        <Text size="xs" tt="uppercase" fw={600} c="var(--app-text-tertiary)" style={{ letterSpacing: '0.06em' }}>
          Saved over {inputs.years} {inputs.years === 1 ? 'year' : 'years'}
        </Text>
        <div className={classes.headline}>{formatMoney(roi.savings)}</div>

        <Group gap="xs" mt="sm" mb="lg">
          <Badge variant="light" size="lg">
            {formatPercent(roi.roi)} ROI
          </Badge>
          <Badge variant="default" size="lg">
            Pays back in {formatMonths(roi.paybackMonths)}
          </Badge>
        </Group>

        <div className={classes.rows}>
          <Row label="The same work, done by people" value={formatMoney(roi.humanCost)} />
          <Row label="The same work, run on Flow" value={formatMoney(roi.aixleCost)} />
          <Row label="Effective cost of an hour on Flow" value={formatMoney(roi.effectiveCostPerHour, 2)} />
          <Row label="ROI" value={formatPercent(roi.roi)} strong />
          <Row label="IRR" value={formatPercent(roi.irr)} />
        </div>

        <Text size="xs" c="var(--app-text-tertiary)" mt={8}>
          An internal rate of return of {formatPercent(IRR_BENCHMARK.low)} to {formatPercent(IRR_BENCHMARK.high)} is
          what a capital project is normally expected to clear.
        </Text>

        <Box className={classes.plan}>
          <Text size="xs" tt="uppercase" fw={600} c="var(--app-text-tertiary)" style={{ letterSpacing: '0.06em' }}>
            What to reserve
          </Text>
          <Group justify="space-between" align="baseline" mt={6}>
            <span className={classes.queueCount}>
              {queues} {queues === 1 ? 'queue' : 'queues'}
            </span>
            <Text fw={600} ff="var(--app-font-mono)">
              {formatMoney(hourlyBill, 2)}/hour
            </Text>
          </Group>
          <Text size="xs" c="var(--app-text-tertiary)" mt={6}>
            Enough to carry this workload through its busy weeks. Change it whenever you like.
          </Text>
          <Button
            component="a"
            href={newWorkspacePath({ sessions: queues })}
            fullWidth
            size="md"
            mt="md"
            rightSection={<IconArrowRight size={16} />}
          >
            Start with {queues} {queues === 1 ? 'queue' : 'queues'}
          </Button>
        </Box>
      </section>
    </div>
  );
};
