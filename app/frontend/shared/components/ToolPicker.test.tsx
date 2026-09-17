import { useState } from 'react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import type { ToolGroup } from 'shared/lib/toolPicker';

import { ToolPicker } from './ToolPicker';

const tools = [
  { id: 10, name: 'Board List Tasks' },
  { id: 11, name: 'Board Move Task' },
  { id: 20, name: 'Slack Post Message' },
  { id: 30, name: 'Echo Greeter' },
];

const groups: ToolGroup[] = [
  { tag: 'board', label: 'Board management', toolIds: [10, 11] },
  { tag: 'slack', label: 'Slack', toolIds: [20] },
];

/** The picker is controlled, so the tests drive it through real state. */
function Harness({ initial = [], ...rest }: { initial?: number[]; tools?: typeof tools; groups?: ToolGroup[] }) {
  const [value, setValue] = useState<number[]>(initial);

  return (
    <ToolPicker
      tools={rest.tools ?? tools}
      groups={rest.groups ?? groups}
      value={value}
      onChange={setValue}
      aria-label="Tools"
      placeholder="Select tools…"
    />
  );
}

const openPicker = async () => {
  await userEvent.click(screen.getByRole('combobox', { name: 'Tools' }));
};

describe('ToolPicker', () => {
  it('offers a group as a collapsed section and keeps its tools out of sight until expanded', async () => {
    renderPage(<Harness />);
    await openPicker();

    expect(await screen.findByRole('checkbox', { name: /Board management/ })).toHaveAttribute('aria-checked', 'false');
    expect(screen.queryByRole('option', { name: 'Board List Tasks' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Expand Board management' }));

    expect(screen.getByRole('option', { name: 'Board List Tasks' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Board Move Task' })).toBeInTheDocument();
  });

  it('attaches every tool in the group from its header', async () => {
    renderPage(<Harness />);
    await openPicker();
    await userEvent.click(await screen.findByRole('checkbox', { name: /Board management/ }));

    expect(screen.getByRole('checkbox', { name: /Board management/ })).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByText('2/2')).toBeInTheDocument();
    // The whole group reads as one chip rather than one chip per member.
    expect(screen.getByRole('button', { name: 'Remove Board management' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Remove Board List Tasks' })).not.toBeInTheDocument();
  });

  it('attaches a single tool out of a group and leaves the rest detached', async () => {
    renderPage(<Harness />);
    await openPicker();
    await userEvent.click(await screen.findByRole('button', { name: 'Expand Board management' }));
    await userEvent.click(screen.getByRole('option', { name: 'Board List Tasks' }));

    expect(screen.getByRole('checkbox', { name: /Board management/ })).toHaveAttribute('aria-checked', 'mixed');
    expect(screen.getByText('1/2')).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Board List Tasks' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('option', { name: 'Board Move Task' })).toHaveAttribute('aria-selected', 'false');
    // A subset is named tool by tool — there is no honest single chip for it.
    expect(screen.getByRole('button', { name: 'Remove Board List Tasks' })).toBeInTheDocument();
  });

  it('opens a half-attached group on its own so the subset can be seen', async () => {
    renderPage(<Harness initial={[10]} />);
    await openPicker();

    expect(await screen.findByRole('option', { name: 'Board List Tasks' })).toBeInTheDocument();
  });

  it('detaches the whole group when its header is clicked again', async () => {
    renderPage(<Harness initial={[10, 11, 30]} />);
    await openPicker();
    await userEvent.click(await screen.findByRole('checkbox', { name: /Board management/ }));

    expect(screen.getByRole('checkbox', { name: /Board management/ })).toHaveAttribute('aria-checked', 'false');
    // The ungrouped tool selected alongside it is untouched.
    expect(screen.getByRole('button', { name: 'Remove Echo Greeter' })).toBeInTheDocument();
  });

  it('removing a group chip detaches every tool it stood for', async () => {
    renderPage(<Harness initial={[10, 11]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Remove Board management' }));
    await openPicker();

    expect(await screen.findByRole('checkbox', { name: /Board management/ })).toHaveAttribute('aria-checked', 'false');
  });

  it('searching a group label offers all of its tools, a tool name only the match', async () => {
    renderPage(<Harness />);
    await openPicker();

    await userEvent.type(screen.getByRole('combobox', { name: 'Tools' }), 'board');
    expect(await screen.findByRole('option', { name: 'Board Move Task' })).toBeInTheDocument();

    await userEvent.clear(screen.getByRole('combobox', { name: 'Tools' }));
    await userEvent.type(screen.getByRole('combobox', { name: 'Tools' }), 'post');
    expect(await screen.findByRole('option', { name: 'Slack Post Message' })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'Board Move Task' })).not.toBeInTheDocument();
  });

  it('lists the tools that carry no group under an Ungrouped heading', async () => {
    renderPage(<Harness />);
    await openPicker();

    const dropdown = await screen.findByRole('listbox');
    expect(within(dropdown).getByText('Ungrouped')).toBeInTheDocument();
    expect(within(dropdown).getByRole('option', { name: 'Echo Greeter' })).toBeInTheDocument();
  });

  it('leaves an opened group open once its header completes it', async () => {
    renderPage(<Harness />);
    await openPicker();
    await userEvent.click(await screen.findByRole('button', { name: 'Expand Board management' }));
    await userEvent.click(screen.getByRole('checkbox', { name: /Board management/ }));

    // Completing the group must not fold the list away under the cursor.
    expect(screen.getByRole('option', { name: 'Board List Tasks' })).toBeInTheDocument();
  });

  it('counts over the matches, not the group, while a search narrows the list', async () => {
    renderPage(<Harness />);
    await openPicker();
    await userEvent.type(screen.getByRole('combobox', { name: 'Tools' }), 'move');

    // One of the two board tools matches — "1/1" alone would read as a full group.
    expect(await screen.findByText('0/1 matched')).toBeInTheDocument();
  });

  it('drops the group chrome entirely when the project offers no groups', async () => {
    renderPage(<Harness groups={[]} />);
    await openPicker();

    expect(await screen.findByRole('option', { name: 'Board List Tasks' })).toBeInTheDocument();
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    expect(screen.queryByText('Ungrouped')).not.toBeInTheDocument();
  });
});
