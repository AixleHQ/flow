export type SkillKind = 'internal' | 'custom';
export type ScopeType = 'Company' | 'Project';
export type ScopeIndicator = 'internal' | 'company' | 'project' | 'overrides_company';

export interface Skill {
  id: number;
  name: string;
  title: string | null;
  content: string | null;
  description: string | null;
  kind: SkillKind;
  scopeType: ScopeType | null;
  scopeId: number | null;
  scopeIndicator: ScopeIndicator;
  internal: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface SkillsFilters {
  search?: string;
}

export interface CreateSkillRequest {
  name: string;
  title: string;
  content: string;
  description?: string;
}

export interface UpdateSkillRequest {
  id: number;
  name?: string;
  title?: string;
  content?: string;
  description?: string;
}
