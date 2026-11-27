import '@testing-library/jest-dom/vitest';
import { Tabs } from '@mantine/core';
import { describe, expect, it } from 'vitest';

import { buildTaskWorkflowRun } from 'test/factories/taskWorkflowRun';
import { renderAuthedPage, screen } from 'test/renderPage';

import { TaskRunsPanel } from './TaskRunsPanel';

function renderPanel(runs: ReturnType<typeof buildTaskWorkflowRun>[]) {
  renderAuthedPage(
    <Tabs value="runs">
      <TaskRunsPanel runs={runs} projectId={7} canRetry={false} retrying={false} onRetry={() => {}} />
    </Tabs>,
  );
}

describe('TaskRunsPanel', () => {
  it("shows a run's duration in its row", () => {
    renderPanel([buildTaskWorkflowRun({ id: 1, durationSeconds: 125 })]);

    expect(screen.getByTestId('run-duration')).toHaveTextContent('2m 5s');
  });

  it('shows no duration for a run without one', () => {
    renderPanel([buildTaskWorkflowRun({ id: 2, durationSeconds: null })]);

    expect(screen.queryByTestId('run-duration')).not.toBeInTheDocument();
  });
});
