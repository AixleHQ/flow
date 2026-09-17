import { describe, expect, it } from 'vitest';

import {
  filterSections,
  sectionState,
  toggleSection,
  toggleTool,
  toolPickerPills,
  toolPickerSections,
  UNGROUPED_KEY,
  type ToolGroup,
} from './toolPicker';

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

const sections = toolPickerSections(tools, groups);
const boardSection = sections[0];

describe('toolPickerSections', () => {
  it('gives each group its own section and sweeps the rest into Ungrouped', () => {
    expect(sections.map((s) => [s.key, s.label, s.tools.map((t) => t.id)])).toEqual([
      ['grp:board', 'Board management', [10, 11]],
      ['grp:slack', 'Slack', [20]],
      [UNGROUPED_KEY, 'Ungrouped', [30]],
    ]);
  });

  it('offers a flat single section when no group is configured', () => {
    const flat = toolPickerSections(tools, []);

    expect(flat).toHaveLength(1);
    expect(flat[0].ungrouped).toBe(true);
    expect(flat[0].tools).toHaveLength(4);
  });

  it('drops a group whose tools are all invisible in this project', () => {
    const keys = toolPickerSections([{ id: 30, name: 'Echo Greeter' }], groups).map((s) => s.key);

    expect(keys).toEqual([UNGROUPED_KEY]);
  });

  it('keeps a group that is only partly visible, listing the tools that exist', () => {
    const board = toolPickerSections([{ id: 10, name: 'Board List Tasks' }], groups)[0];

    expect(board.tools).toEqual([{ id: 10, name: 'Board List Tasks' }]);
  });
});

describe('sectionState', () => {
  it('reports none, partial and all', () => {
    expect(sectionState(boardSection, [])).toBe('none');
    expect(sectionState(boardSection, [10])).toBe('partial');
    expect(sectionState(boardSection, [10, 11])).toBe('all');
  });
});

describe('toggleSection', () => {
  it('fills a group that is empty or half attached, keeping other ids', () => {
    expect(toggleSection(boardSection, [30])).toEqual([30, 10, 11]);
    expect(toggleSection(boardSection, [30, 10])).toEqual([30, 10, 11]);
  });

  it('clears a fully attached group and leaves everything else alone', () => {
    expect(toggleSection(boardSection, [10, 11, 30])).toEqual([30]);
  });
});

describe('toggleTool', () => {
  it('attaches and detaches a single tool without touching its group siblings', () => {
    expect(toggleTool(11, [10])).toEqual([10, 11]);
    expect(toggleTool(11, [10, 11])).toEqual([10]);
  });

  it('keeps a half-attached group half attached across a round trip', () => {
    const ids = toggleTool(10, []);

    expect(sectionState(boardSection, ids)).toBe('partial');
    expect(ids).toEqual([10]);
  });
});

describe('toolPickerPills', () => {
  it('collapses a fully attached group into one chip', () => {
    expect(toolPickerPills(sections, [10, 11])).toEqual([
      { key: 'grp:board', label: 'Board management', toolIds: [10, 11] },
    ]);
  });

  it('names each tool when a group is only partly attached', () => {
    expect(toolPickerPills(sections, [10])).toEqual([{ key: 'tool:10', label: 'Board List Tasks', toolIds: [10] }]);
  });

  it('never collapses the ungrouped bucket into a chip of its own', () => {
    expect(toolPickerPills(sections, [30])).toEqual([{ key: 'tool:30', label: 'Echo Greeter', toolIds: [30] }]);
  });

  it('ignores an id that matches no visible tool', () => {
    expect(toolPickerPills(sections, [999])).toEqual([]);
  });
});

describe('filterSections', () => {
  it('keeps every member of a group whose own label matches', () => {
    expect(filterSections(sections, 'board')).toEqual([boardSection]);
  });

  it('narrows a group to the tools that match', () => {
    const [slack] = filterSections(sections, 'post');

    expect(slack.tools.map((t) => t.id)).toEqual([20]);
  });

  it('returns nothing when the query matches no group and no tool', () => {
    expect(filterSections(sections, 'nothing-here')).toEqual([]);
  });
});
