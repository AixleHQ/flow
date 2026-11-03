import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildRunnerBadge } from 'test/factories/runner';
import { buildTaskWorkflowRun } from 'test/factories/taskWorkflowRun';
import { renderAuthedPage, screen } from 'test/renderPage';

import { RunTileRow } from './RunTileRow';

const ON = { features: { externalRunners: true } };

// The board task's run history and its "Latest run" tile both render this row, so the
// "Runs on" badge is checked here once for both.
describe('RunTileRow', () => {
  it("shows the run's runner, linking to the runner, with the flag on", () => {
    const run = buildTaskWorkflowRun({ runnerId: 4, runner: buildRunnerBadge({ id: 4, name: 'Prod VPC' }) });
    renderAuthedPage(<RunTileRow run={run} projectId={7} />, { props: ON });

    expect(screen.getByRole('link', { name: 'Prod VPC · Manual' })).toHaveAttribute(
      'href',
      '/company/projects/7/runners/4',
    );
  });

  it('says Hosted for a run without a runner, with the flag on', () => {
    renderAuthedPage(<RunTileRow run={buildTaskWorkflowRun()} projectId={7} />, { props: ON });

    expect(screen.getByText('Hosted')).toBeInTheDocument();
  });

  it('renders no badge without the flag', () => {
    const run = buildTaskWorkflowRun({ runnerId: 4, runner: buildRunnerBadge({ id: 4, name: 'Prod VPC' }) });
    renderAuthedPage(<RunTileRow run={run} projectId={7} />, { props: { features: { externalRunners: false } } });

    expect(screen.queryByText('Hosted')).not.toBeInTheDocument();
    expect(screen.queryByText('Prod VPC · Manual')).not.toBeInTheDocument();
    expect(screen.getByText('Implement Feature')).toBeInTheDocument();
  });
});
