export type ConfigItemType = 'secret' | 'variable';
export type ScopeType = 'Company' | 'Project';
export type ScopeIndicator = 'company' | 'project' | 'overrides_company';

export interface ConfigItem {
  id: number;
  name: string;
  value: string; // Masked "••••••••" for secrets
  description: string | null;
  itemType: ConfigItemType;
  scopeType: ScopeType;
  scopeId: number;
  scopeIndicator: ScopeIndicator;
  valueEditable: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface ConfigItemsFilters {
  itemType?: ConfigItemType;
  search?: string;
}

export interface CreateConfigItemRequest {
  name: string;
  value: string;
  description?: string;
  itemType: ConfigItemType;
}

export interface UpdateConfigItemRequest {
  id: number;
  name?: string;
  value?: string;
  description?: string;
}
