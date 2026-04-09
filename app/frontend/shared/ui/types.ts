export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'claude_code';
export type UserRole = 'employee' | 'admin' | 'super_admin';

export interface AgentCredential {
  id: number;
  agentType: AgentType;
  configKeys: string[];
  defaultModel: string | null;
  lastUsedAt: string | null;
  expiresAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface SharedUser {
  id: number;
  email: string;
  name: string;
  role: UserRole;
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
  company: SharedCompany | null;
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
  sentryFrontendDsn: string | null;
  appVersion: string | null;
}

export interface SharedPermissions {
  isAdmin: boolean;
  canManageMembers: boolean;
  canManageProjects: boolean;
}

export interface SharedProps {
  currentUser: SharedUser | null;
  flash: Record<string, string>;
  projects?: SharedProject[];
  permissions?: SharedPermissions;
  settings: SharedSettings;
  [key: string]: unknown;
}
