export type AgentType = 'codex' | 'cursor_cli' | 'open_code' | 'claude_code';

export interface User {
  id: number;
  email: string;
  name: string;
  onboardingCompleted: boolean;
  selectedAgents: AgentType[];
  configuredAgents: AgentType[];
  pendingAgents: AgentType[];
}

export interface CompanyBranding {
  name: string;
  logoUrl: string | null;
  primaryColor: string;
  secondaryColor: string;
}

export interface Company {
  id: number;
  name: string;
  slug: string;
  branding: CompanyBranding;
}

export interface CurrentUserResponse {
  user: User;
  company: Company;
}
