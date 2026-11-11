import type { ComboboxData } from '@mantine/core';

export interface BoardTeam {
  id: number;
  name: string;
}

/** A task is assigned to one person or one team, never both. */
export interface Assignee {
  kind: 'user' | 'team';
  id: number;
}

/** The value an assignee takes in a Select: `user:3`, `team:7`. */
export function assigneeKey(assignee: Assignee | null): string | null {
  return assignee ? `${assignee.kind}:${assignee.id}` : null;
}

export function parseAssigneeKey(key: string | null): Assignee | null {
  const match = /^(user|team):(\d+)$/.exec(key ?? '');
  return match ? { kind: match[1] as Assignee['kind'], id: Number(match[2]) } : null;
}

export function taskAssignee(task: { assigneeId: number | null; assigneeTeamId?: number | null }): Assignee | null {
  if (task.assigneeTeamId) return { kind: 'team', id: task.assigneeTeamId };
  if (task.assigneeId) return { kind: 'user', id: task.assigneeId };
  return null;
}

/** Both fields, so assigning one kind clears the other. */
export function assigneeFields(assignee: Assignee | null): {
  assigneeId: number | null;
  assigneeTeamId: number | null;
} {
  return {
    assigneeId: assignee?.kind === 'user' ? assignee.id : null,
    assigneeTeamId: assignee?.kind === 'team' ? assignee.id : null,
  };
}

export function assigneeSelectData(members: Array<{ id: number; name: string }>, teams: BoardTeam[]): ComboboxData {
  const people = members.map((m) => ({ value: assigneeKey({ kind: 'user', id: m.id }) as string, label: m.name }));
  if (teams.length === 0) return people;

  return [
    { group: 'People', items: people },
    {
      group: 'Teams',
      items: teams.map((t) => ({ value: assigneeKey({ kind: 'team', id: t.id }) as string, label: t.name })),
    },
  ];
}
