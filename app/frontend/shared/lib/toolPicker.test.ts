import { describe, expect, it } from 'vitest';

import { toolIdsFromPickerValue, toolPickerData, toolPickerValue, type ToolGroup } from './toolPicker';

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

describe('toolPicker', () => {
  it('offers each group once and keeps its members out of the flat list', () => {
    expect(toolPickerData(tools, groups)).toEqual([
      { value: 'grp:board', label: 'Board management' },
      { value: 'grp:slack', label: 'Slack' },
      { value: '30', label: 'Echo Greeter' },
    ]);
  });

  it('lists every tool individually when no group is offered', () => {
    expect(toolPickerData(tools, [])).toHaveLength(4);
  });

  it('collapses grouped ids into their token and leaves ungrouped ids alone', () => {
    expect(toolPickerValue([10, 11, 30], groups)).toEqual(['grp:board', '30']);
  });

  it('expands a group token back into every member id', () => {
    expect(toolIdsFromPickerValue(['grp:board', '30'], groups)).toEqual([10, 11, 30]);
    expect(toolIdsFromPickerValue(['grp:board', 'grp:slack'], groups)).toEqual([10, 11, 20]);
  });

  it('round-trips a selection of whole groups', () => {
    const ids = toolIdsFromPickerValue(toolPickerValue([10, 11, 20], groups), groups);

    expect(ids).toEqual([10, 11, 20]);
  });
});
