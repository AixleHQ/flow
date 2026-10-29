import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { buildRunnerBadge, buildRunnerSummary } from 'test/factories/runner';
import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import { RunnerSelect, RunsOnBadge } from './runnerChoice';
import { runnerUnusableReason } from './runnerCopy';

const ON = { features: { externalRunners: true } };

describe('RunsOnBadge', () => {
  it('says Hosted for a run without a runner', () => {
    renderAuthedPage(<RunsOnBadge runner={null} projectId={7} />, { props: ON });

    expect(screen.getByText('Hosted')).toBeInTheDocument();
  });

  it("names the runner and its type, linking to the runner's page", () => {
    renderAuthedPage(<RunsOnBadge runner={buildRunnerBadge({ id: 4, name: 'Prod VPC' })} projectId={7} />, {
      props: ON,
    });

    expect(screen.getByRole('link', { name: 'Prod VPC · Manual' })).toHaveAttribute(
      'href',
      '/company/projects/7/runners/4',
    );
  });

  it('names a deleted runner without a link', () => {
    renderAuthedPage(<RunsOnBadge runner={buildRunnerBadge({ name: 'Old box', deleted: true })} projectId={7} />, {
      props: ON,
    });

    expect(screen.getByText('Old box · Manual')).toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });

  it('renders nothing without the flag', () => {
    renderAuthedPage(<RunsOnBadge runner={null} projectId={7} />, { props: { features: { externalRunners: false } } });

    expect(screen.queryByText('Hosted')).not.toBeInTheDocument();
  });
});

describe('RunnerSelect', () => {
  const runners = [
    buildRunnerSummary({ id: 1, name: 'Prod VPC', status: 'connected' }),
    buildRunnerSummary({ id: 2, name: 'Spare', status: 'disabled' }),
  ];

  it('offers hosted and each runner with its status, and reports the pick', async () => {
    const onChange = vi.fn();
    renderAuthedPage(
      <RunnerSelect label="Runs on" hostedLabel="Hosted" runners={runners} value={null} onChange={onChange} />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: 'Runs on' }));
    expect(await screen.findByRole('option', { name: 'Spare · Disabled' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('option', { name: 'Prod VPC · Connected' }));

    expect(onChange).toHaveBeenCalledWith(1);
  });

  it('turns every runner off for an interactive session', async () => {
    renderAuthedPage(
      <RunnerSelect
        label="Runs on"
        hostedLabel="Hosted"
        runners={runners}
        value={null}
        onChange={vi.fn()}
        interactive
      />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: 'Runs on' }));

    const option = await screen.findByRole('option', {
      name: "Prod VPC · Connected · can't run interactive sessions yet",
    });
    expect(option).toHaveAttribute('data-combobox-disabled', 'true');
  });
});

describe('runnerUnusableReason', () => {
  it('names a disabled, revoked or deleted runner, and nothing else', () => {
    expect(runnerUnusableReason(buildRunnerSummary({ name: 'X', status: 'disabled' }))).toBe('Runner "X" is disabled.');
    expect(runnerUnusableReason(buildRunnerSummary({ name: 'X', status: 'revoked' }))).toBe('Runner "X" is revoked.');
    expect(runnerUnusableReason(buildRunnerSummary({ name: 'X', deleted: true }))).toBe('Runner "X" is deleted.');
    expect(runnerUnusableReason(buildRunnerSummary({ status: 'degraded' }))).toBeNull();
  });
});
