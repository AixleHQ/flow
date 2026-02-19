export type IntegrationProvider = 'github' | 'linear';
export type IntegrationStatus = 'active' | 'inactive' | 'error';

export interface IntegrationConnectedBy {
  id: number;
  name: string;
  email: string;
}

export interface Integration {
  id: number;
  name: string;
  provider: IntegrationProvider;
  status: IntegrationStatus;
  settings: Record<string, unknown>;
  connectedBy: IntegrationConnectedBy;
  createdAt: string;
  updatedAt: string;
  githubUrl: string | null;
}

export interface CreateGithubIntegrationRequest {
  installationId: string;
}
