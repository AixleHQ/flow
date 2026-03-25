export type ScopeIndicator = 'company' | 'project';

export interface RepositoryIntegration {
  id: number;
  name: string;
  provider: string;
}

export interface Repository {
  id: number;
  fullName: string;
  repoName: string;
  sourceBranch: string;
  cloneUrl: string;
  isPrivate: boolean;
  description: string | null;
  purpose: string | null;
  lastFetchedAt: string | null;
  scopeType: string;
  scopeId: number;
  scopeIndicator: ScopeIndicator;
  integration: RepositoryIntegration;
  createdAt: string;
}

export interface AvailableRepo {
  fullName: string;
  defaultBranch: string;
  cloneUrl: string;
  isPrivate: boolean;
  description: string | null;
}

export interface UpdateRepositoryRequest {
  sourceBranch?: string;
  purpose?: string;
}

export interface CreateRepositoryRequest {
  integrationId: number;
  fullName: string;
  sourceBranch?: string;
  purpose?: string;
}

export interface WebhookInfo {
  url: string;
  secretToken: string;
  trigger: string;
}
