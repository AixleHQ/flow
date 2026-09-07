export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'antigravity_cli' | 'claude_code' | 'grok';
export type UserRole = 'employee' | 'admin' | 'super_admin' | 'viewer';

export interface ProjectPermissions {
  canExecute: boolean;
  canManage: boolean;
}

export interface AgentCredential {
  id: number;
  agentType: AgentType;
  configKeys: string[];
  defaultModel: string | null;
  lastUsedAt: string | null;
  expiresAt: string | null;
  connectionStatus: 'active' | 'expiring' | 'expired';
  createdAt: string;
  updatedAt: string;
}

// A membership role is always company-scoped — super_admin is platform-level
// and only ever appears in SharedUser.currentRole.
type MembershipRole = Exclude<UserRole, 'super_admin'>;

export interface SharedMembership {
  id: number;
  role: MembershipRole;
  state: string;
  company: SharedCompany;
}

export interface SharedUser {
  id: number;
  email: string;
  name: string;
  state: string;
  position: string | null;
  preferredAgentLanguage: string;
  selectedAgents: AgentType[];
  onboardingState: string;
  onboardingCompletedAt: string | null;
  defaultAgentCredentialId: number | null;
  defaultAgentRuntime: AgentType | null;
  configuredAgents: AgentType[];
  agentCredentials: AgentCredential[];
  // Who may open this person's sessions besides themselves: while a session runs
  // (live terminal + editor) and once it is over (replayed log). Global, not
  // per-company — see TerminalSession#visible_to?.
  shareActiveSessions: boolean;
  shareCompletedSessions: boolean;
  // True when onboarding skipped the agent step (viewer everywhere) but the user
  // has since gained a role that can run things — drives the sidebar nudge.
  needsAgentSetup: boolean;
  // Request-scoped: the company/role of the session's current membership.
  currentCompany: SharedCompany | null;
  currentRole: UserRole | null;
  // Active memberships only (drives the sidebar switcher + profile Companies card).
  memberships: SharedMembership[];
}

export interface SharedCompany {
  id: number;
  name: string;
  emailDomain: string;
  logoUrl: string | null;
  primaryColor: string | null;
  secondaryColor: string | null;
}

export interface SharedProject {
  id: number;
  name: string;
  slug: string;
  state: string;
}

export interface SharedSettings {
  env: string;
  domain: string;
  githubAppSlug: string | null;
  appVersion: string | null;
  sentryFrontendDsn: string | null;
}

export interface SharedPermissions {
  isAdmin: boolean;
  canManageMembers: boolean;
  canManageProjects: boolean;
}

export interface SharedProps {
  currentUser: SharedUser | null;
  // Most flash entries are strings (notice/alert). `needs_setup` is a list of
  // "what was not copied / needs setup" messages surfaced after a catalog copy.
  flash: Record<string, string | string[] | undefined>;
  projects?: SharedProject[];
  permissions?: SharedPermissions;
  settings: SharedSettings;
  [key: string]: unknown;
}
