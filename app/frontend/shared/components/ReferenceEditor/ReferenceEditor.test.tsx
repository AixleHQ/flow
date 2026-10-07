import {
  acceptCompletion,
  completionStatus,
  currentCompletions,
  setSelectedCompletion,
  startCompletion,
} from '@codemirror/autocomplete';
import { EditorView } from '@codemirror/view';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, waitFor, within } from 'test/renderPage';

import { ReferenceEditor, type ReferenceItem } from './ReferenceEditor';

const GROUPS = ['Assets', 'Sessions', 'Connections'];

const ITEMS: ReferenceItem[] = [
  { token: '{{asset:12}}', kind: 'asset', label: 'brand-guide.pdf', hint: 'Attached', group: 'Assets' },
  { token: '{{asset:13}}', kind: 'asset', label: 'notes.md', hint: 'Project asset', group: 'Assets' },
  {
    token: '{{output:3:summary.md}}',
    kind: 'output',
    label: 'summary.md',
    hint: 'Output of Report',
    group: 'Assets',
    disabledReason: 'Runs after this session',
  },
  { token: '{{step:2}}', kind: 'step', label: 'Collect', hint: 'Session 1 · runs before', group: 'Sessions' },
  { token: '{{mcp:7}}', kind: 'mcp', label: 'GitHub', hint: 'Workflow base · http', group: 'Connections' },
];

function renderEditor(props: Partial<Parameters<typeof ReferenceEditor>[0]> = {}) {
  const onChange = vi.fn();
  const onInsert = vi.fn();
  renderPage(
    <ReferenceEditor
      value=""
      onChange={onChange}
      onInsert={onInsert}
      items={ITEMS}
      groups={GROUPS}
      ariaLabel="Session instructions"
      {...props}
    />,
  );
  const textbox = screen.getByRole('textbox', { name: 'Session instructions' });
  const view = EditorView.findFromDOM(textbox);
  if (!view) throw new Error('no editor view');
  return { textbox, view, onChange, onInsert };
}

function typeAt(view: EditorView, text: string) {
  const at = view.state.doc.length;
  view.dispatch({
    changes: { from: at, insert: text },
    selection: { anchor: at + text.length },
    userEvent: 'input.type',
  });
}

describe('ReferenceEditor', () => {
  it('renders known tokens as named pills and unknown ones as broken', () => {
    const { textbox } = renderEditor({
      value: 'Read {{asset:12}} with {{mcp:7}}, then {{asset:99}} and {{step:x}}.',
      readOnly: true,
    });

    expect(within(textbox).getByText('brand-guide.pdf')).toBeInTheDocument();
    expect(within(textbox).getByText('GitHub')).toBeInTheDocument();
    expect(within(textbox).getByText('Missing asset #99')).toBeInTheDocument();
    expect(within(textbox).getByText('Invalid reference')).toBeInTheDocument();
    expect(within(textbox).queryByText(/\{\{asset:12\}\}/)).not.toBeInTheDocument();
  });

  it('shows a pending pill, not a broken one, while the catalog is loading', () => {
    const { textbox } = renderEditor({ value: 'Read {{asset:99}}', items: [], loading: true });

    expect(within(textbox).getByText('Asset #99')).toBeInTheDocument();
    expect(within(textbox).queryByText('Missing asset #99')).not.toBeInTheDocument();
  });

  it('cannot be edited when read-only', () => {
    const { textbox, view } = renderEditor({ value: 'Read {{asset:12}}', readOnly: true });

    expect(textbox).toHaveAttribute('contenteditable', 'false');
    expect(view.state.readOnly).toBe(true);
  });

  it('offers the catalog grouped after "@" and inserts the chosen token', async () => {
    const { view, onChange, onInsert } = renderEditor();

    typeAt(view, 'Use @gi');
    startCompletion(view);
    await waitFor(() => expect(completionStatus(view.state)).toBe('active'));

    expect(currentCompletions(view.state).map((c) => c.label)).toEqual(['GitHub']);
    // The editor ignores Enter for a moment after the list opens, so fast typing does not pick a row.
    await waitFor(() => expect(acceptCompletion(view)).toBe(true));

    expect(view.state.doc.toString()).toBe('Use {{mcp:7}} ');
    expect(onChange).toHaveBeenLastCalledWith('Use {{mcp:7}} ');
    expect(onInsert).toHaveBeenCalledWith(expect.objectContaining({ token: '{{mcp:7}}' }));
  });

  it('lists groups in order, filters by hint, and puts disabled rows last without inserting them', async () => {
    const { view, onInsert } = renderEditor();

    typeAt(view, '@');
    startCompletion(view);
    await waitFor(() => expect(completionStatus(view.state)).toBe('active'));
    expect(currentCompletions(view.state).map((c) => c.label)).toEqual([
      'brand-guide.pdf',
      'notes.md',
      'summary.md',
      'Collect',
      'GitHub',
    ]);

    typeAt(view, 'report');
    startCompletion(view);
    await waitFor(() => expect(currentCompletions(view.state).map((c) => c.label)).toEqual(['summary.md']));
    view.dispatch({ effects: setSelectedCompletion(0) });
    await waitFor(() => expect(acceptCompletion(view)).toBe(true));

    expect(view.state.doc.toString()).toBe('@report');
    expect(onInsert).not.toHaveBeenCalled();
  });

  it('does not open the picker for an "@" inside a word', async () => {
    const { view } = renderEditor();

    typeAt(view, 'mail me at ops@gi');
    startCompletion(view);

    await waitFor(() => expect(completionStatus(view.state)).toBeNull());
  });

  it('deletes a whole token with one Backspace', () => {
    const { view, onChange } = renderEditor({ value: 'Read {{asset:12}}' });

    view.dispatch({ selection: { anchor: view.state.doc.length } });
    view.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', bubbles: true }));

    expect(view.state.doc.toString()).toBe('Read ');
    expect(onChange).toHaveBeenLastCalledWith('Read ');
  });

  it('takes a new value from its parent without reporting it back as an edit', () => {
    const onChange = vi.fn();
    const { rerender } = renderPage(
      <ReferenceEditor value="a" onChange={onChange} items={ITEMS} groups={GROUPS} ariaLabel="Notes" />,
    );
    rerender(
      <ReferenceEditor value="Read {{asset:12}}" onChange={onChange} items={ITEMS} groups={GROUPS} ariaLabel="Notes" />,
    );

    expect(within(screen.getByRole('textbox', { name: 'Notes' })).getByText('brand-guide.pdf')).toBeInTheDocument();
    expect(onChange).not.toHaveBeenCalled();
  });
});
