import type { CurrentUser, Project } from '@/types/generated';

export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'antigravity_cli' | 'claude_code' | 'grok' | 'kiro_cli';
export type UserRole = 'employee' | 'admin' | 'super_admin' | 'viewer';

// Both lists are kept here by hand (agentRuntimes.ts and the role labels are keyed by them), while
// the server's own lists — CompanyMembership::AVAILABLE_AGENTS and the membership roles — reach the
// generated types. These stop tsc the moment the two differ, e.g. a runtime added on the server only.
type SameUnion<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;
type Expect<T extends true> = T;
export type AgentTypeMatchesServer = Expect<SameUnion<AgentType, NonNullable<CurrentUser['defaultAgentRuntime']>>>;
export type UserRoleMatchesServer = Expect<SameUnion<UserRole, NonNullable<CurrentUser['currentRole']>>>;

export interface ProjectPermissions {
  canExecute: boolean;
  canManage: boolean;
  canManageCompany?: boolean;
}

export type SharedProject = Pick<Project, 'id' | 'name' | 'slug' | 'state' | 'favorite'>;

export interface SharedSettings {
  env: string;
  domain: string;
  githubAppSlug: string | null;
  appVersion: string | null;
  sentryFrontendDsn: string | null;
  sentryTracesSampleRate?: number;
}

export interface SharedPermissions {
  isAdmin: boolean;
  canManageMembers: boolean;
  canManageProjects: boolean;
  /** False for a viewer. Optional: a page served by an older pod does not send it. */
  canWrite?: boolean;
}

export interface SharedProps {
  currentUser: CurrentUser | null;
  // Most flash entries are strings (notice/alert). `needs_setup` is a list of
  // "what was not copied / needs setup" messages surfaced after a catalog copy.
  flash: Record<string, string | string[] | undefined>;
  projects?: SharedProject[];
  permissions?: SharedPermissions;
  settings: SharedSettings;
  [key: string]: unknown;
}
