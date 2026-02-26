export type ToolKind = 'custom' | 'system' | 'internal' | 'workflow';
export type ScopeType = 'Company' | 'Project';
export type ScopeIndicator = 'system' | 'company' | 'project' | 'overrides_company';

export interface ToolFile {
  id?: number;
  path: string;
  content: string;
  binary: boolean;
  fileName: string | null;
  fileUrl: string | null;
  _destroy?: boolean;
}

export interface ToolFileInput {
  id?: number;
  path: string;
  content?: string;
  _destroy?: boolean;
}

export interface Tool {
  id: number;
  name: string;
  displayName: string;
  description: string | null;
  kind: ToolKind;
  scopeType: ScopeType | null;
  scopeId: number | null;
  dockerImage: string | null;
  command: string | null;
  requiredConfigItems: string[];
  inputSchema: Record<string, unknown>;
  enabled: boolean;
  scopeIndicator: ScopeIndicator;
  platformTool: boolean;
  toolFiles: ToolFile[];
  createdAt: string;
  updatedAt: string;
}

export interface ToolsFilters {
  search?: string;
  kind?: ToolKind | 'all';
}

export interface CreateToolRequest {
  name: string;
  displayName: string;
  description?: string;
  dockerImage: string;
  command?: string;
  requiredConfigItems?: string[];
  inputSchema?: Record<string, unknown>;
  toolFilesAttributes?: ToolFileInput[];
}

export interface UpdateToolRequest {
  id: number;
  name?: string;
  displayName?: string;
  description?: string;
  dockerImage?: string;
  command?: string;
  requiredConfigItems?: string[];
  inputSchema?: Record<string, unknown>;
  enabled?: boolean;
  toolFilesAttributes?: ToolFileInput[];
}
