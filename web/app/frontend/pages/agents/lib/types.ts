export type AgentSource = 'custom' | 'bmad_import';
export type ScopeType = 'Company' | 'Project';
export type ScopeIndicator = 'company' | 'project' | 'overrides_company';

export interface Agent {
  id: number;
  name: string; // lowercase_underscore identifier
  title: string; // display title
  icon: string | null; // emoji
  persona: string;
  communicationStyle: string | null;
  principles: string | null;
  source: AgentSource;
  scopeType: ScopeType;
  scopeId: number;
  scopeIndicator: ScopeIndicator;
  createdAt: string;
  updatedAt: string;
}

export interface AgentsFilters {
  search?: string;
}

export interface CreateAgentRequest {
  name: string;
  title: string;
  icon?: string;
  persona: string;
  communicationStyle?: string;
  principles?: string;
}

export interface UpdateAgentRequest {
  id: number;
  name?: string;
  title?: string;
  icon?: string;
  persona?: string;
  communicationStyle?: string;
  principles?: string;
}
