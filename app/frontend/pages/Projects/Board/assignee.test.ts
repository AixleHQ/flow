import { describe, expect, it } from 'vitest';

import { assigneeFields, assigneeKey, assigneeSelectData, parseAssigneeKey, taskAssignee } from './assignee';

describe('board assignee', () => {
  it('reads a team assignee before a person, since a task holds one or the other', () => {
    expect(taskAssignee({ assigneeId: null, assigneeTeamId: 7 })).toEqual({ kind: 'team', id: 7 });
    expect(taskAssignee({ assigneeId: 3, assigneeTeamId: null })).toEqual({ kind: 'user', id: 3 });
    expect(taskAssignee({ assigneeId: null })).toBeNull();
  });

  it('round-trips through the Select value', () => {
    expect(parseAssigneeKey(assigneeKey({ kind: 'team', id: 7 }))).toEqual({ kind: 'team', id: 7 });
    expect(parseAssigneeKey(null)).toBeNull();
    expect(parseAssigneeKey('nonsense')).toBeNull();
  });

  it('sends both fields so that one kind of assignee replaces the other', () => {
    expect(assigneeFields({ kind: 'team', id: 7 })).toEqual({ assigneeId: null, assigneeTeamId: 7 });
    expect(assigneeFields({ kind: 'user', id: 3 })).toEqual({ assigneeId: 3, assigneeTeamId: null });
    expect(assigneeFields(null)).toEqual({ assigneeId: null, assigneeTeamId: null });
  });

  it('groups people and teams only when the project has teams', () => {
    const members = [{ id: 3, name: 'Anna' }];
    expect(assigneeSelectData(members, [])).toEqual([{ value: 'user:3', label: 'Anna' }]);
    expect(assigneeSelectData(members, [{ id: 7, name: 'Planner' }])).toEqual([
      { group: 'People', items: [{ value: 'user:3', label: 'Anna' }] },
      { group: 'Teams', items: [{ value: 'team:7', label: 'Planner' }] },
    ]);
  });
});
