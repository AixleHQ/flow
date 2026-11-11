import type ProjectTeam from '@/types/generated/ProjectTeam';

type TeamMember = ProjectTeam['members'][number];

export const buildTeamMember = (overrides: Partial<TeamMember> = {}): TeamMember => ({
  id: 2,
  name: 'Bo Member',
  email: 'bo@apollo.test',
  status: { state: 'ready', until: null, detail: null },
  runtimes: [{ agentType: 'kiro_cli', label: 'Kiro CLI', quotaExhaustedUntil: null }],
  ...overrides,
});

export const buildProjectTeam = (overrides: Partial<ProjectTeam> = {}): ProjectTeam => ({
  id: 1,
  name: 'Planner',
  projectId: 7,
  strategy: 'priority',
  members: [buildTeamMember()],
  nextMemberId: null,
  triggers: [],
  triggerCount: 0,
  taskCount: 0,
  ...overrides,
});
