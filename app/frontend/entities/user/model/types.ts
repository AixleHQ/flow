export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'claude_code';
export type UserRole = 'employee' | 'admin' | 'super_admin';
export type UserState = 'active' | 'pending' | 'suspended' | 'archived';
export type UserPosition = 'qa' | 'pm_po_ba' | 'dev' | 'designer' | 'cto';
export type OnboardingState = 'step1' | 'step2' | 'step3' | 'step4' | 'completed';
export type OnboardingEvent = 'go_next' | 'go_previous' | 'complete';

export interface IUser {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  state: UserState;
  position: UserPosition | null;
  preferredAgentLanguage: string;
  onboardingState: OnboardingState;
}

export interface ICompanyBranding {
  name: string;
  emailDomain: string;
  logoUrl: string | null;
  primaryColor: string;
  secondaryColor: string;
}

export interface ICompany {
  id: number;
  name: string;
  emailDomain: string;
  logoUrl: string | null;
  primaryColor: string;
  secondaryColor: string;
}

// Agent credential info (without sensitive data)
export interface IAgentCredential {
  id: number;
  agentType: AgentType;
  configKeys: string[];
  defaultModel: string | null;
  lastUsedAt: string | null;
  expiresAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CurrentUserResponse {
  id: number;
  email: string;
  name: string;
  role: UserRole;
  state: UserState;
  position: UserPosition | null;
  preferredAgentLanguage: string;
  selectedAgents: AgentType[];
  configuredAgents: AgentType[];
  agentCredentials: IAgentCredential[];
  onboardingState: OnboardingState;
  onboardingCompletedAt: string | null;
  defaultAgentCredentialId: number | null;
  defaultAgentRuntime: AgentType | null;
  company: ICompany | null;
}
