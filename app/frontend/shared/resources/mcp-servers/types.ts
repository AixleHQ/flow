export type McpServerKind = 'internal' | 'custom';
export type Transport = 'http' | 'sse' | 'stdio';

export interface McpServer {
  id: number;
  name: string;
  url: string | null;
  transport: Transport;
  headers: Record<string, string> | null;
  description: string | null;
  kind: McpServerKind;
  scopeType: string | null;
  scopeId: number | null;
  scopeIndicator: string;
  enabled: boolean;
  internal: boolean;
  command: string | null;
  env: Record<string, string> | null;
  // OAuth (oauth-unification §4.3/§4.6). oauthStatus is per-current-user and read-only.
  authType?: 'none' | 'static' | 'oauth';
  credentialScope?: 'shared' | 'per_user';
  oauthStatus?: 'pending' | 'active' | 'expiring' | 'error' | null;
  // Connector provenance and tool-baseline health. Null/false on hand-authored
  // servers — nobody promised anything about a server someone typed in.
  connectorName?: string | null;
  connectorVersion?: string | null;
  connectorStatus?: 'active' | 'deprecated' | 'deleted' | null;
  connectorVersionPinned?: boolean;
  toolBaseline?: boolean;
  toolDrift?: { added?: string[]; removed?: string[]; changed?: string[]; detected_at?: string } | null;
  /** Version the catalog now carries, when it differs from the installed one. */
  connectorUpdateVersion?: string | null;
  createdAt: string;
  updatedAt: string;
}
