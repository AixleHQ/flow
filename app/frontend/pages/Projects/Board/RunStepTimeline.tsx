import { Box, Button, Text } from '@mantine/core';
import { useState } from 'react';

import { formatDuration } from './boardFormat';
import type { TaskWorkflowRun } from './taskRuns';

type RunStep = NonNullable<TaskWorkflowRun['steps']>[number];

const stepDotColor = (state: string): string => {
  if (state === 'done') return 'var(--app-success-fg)';
  if (state === 'running') return 'var(--app-warning-fg)';
  if (state === 'failed') return 'var(--app-danger-fg)';
  return 'var(--mantine-color-gray-5)';
};

// A run's steps as a dotted timeline. Long runs are cut to the first three steps behind a
// show-all toggle, so a 12-step workflow does not push the rest of the Runs tab off screen.
export function RunStepTimeline({ steps }: { steps: RunStep[] }) {
  const [showAllSteps, setShowAllSteps] = useState(false);

  return (
    <Box mt="xs">
      {steps.map((step, i) => {
        const isHidden = !showAllSteps && i > 2;
        return (
          <Box
            key={i}
            style={{
              display: isHidden ? 'none' : 'flex',
              gap: 10,
              paddingTop: 8,
              paddingBottom: 8,
              borderBottom: '1px solid var(--app-border-default)',
            }}
          >
            <Box
              w={8}
              h={8}
              mt={4}
              style={{ borderRadius: '50%', flexShrink: 0, backgroundColor: stepDotColor(step.state) }}
            />
            <Box style={{ flex: 1 }}>
              <Text size="sm" c={step.state === 'waiting' ? 'dimmed' : undefined}>
                {step.name}
              </Text>
              <Text size="xs" c="dimmed" ff="monospace">
                {step.durationSeconds != null ? formatDuration(step.durationSeconds) : '—'}
              </Text>
            </Box>
          </Box>
        );
      })}
      {steps.length > 3 && (
        <Button variant="subtle" size="xs" mt={8} onClick={() => setShowAllSteps((s) => !s)}>
          {showAllSteps ? 'Show fewer steps' : `Show all ${steps.length} steps`}
        </Button>
      )}
    </Box>
  );
}
