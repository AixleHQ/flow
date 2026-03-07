export type McpTransport = 'http' | 'sse' | 'stdio';

export interface McpServer {
  id: number;
  name: string;
  displayName: string;
  url: string | null;
  transport: McpTransport;
  headers: Record<string, string>;
  command: string | null;
  env: Record<string, string>;
  description: string | null;
  kind: 'internal' | 'custom';
  scopeType: string | null;
  scopeId: number | null;
  enabled: boolean;
  scopeIndicator: 'internal' | 'company' | 'project' | 'overrides_company';
  internal: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateMcpServerDto {
  name: string;
  displayName: string;
  url?: string;
  transport?: McpTransport;
  headers?: Record<string, string>;
  command?: string;
  env?: Record<string, string>;
  description?: string;
  enabled?: boolean;
}

export interface UpdateMcpServerDto {
  name?: string;
  displayName?: string;
  url?: string;
  transport?: McpTransport;
  headers?: Record<string, string>;
  command?: string;
  env?: Record<string, string>;
  description?: string;
  enabled?: boolean;
}
