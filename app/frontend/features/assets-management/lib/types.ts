export type ScopeType = 'Company' | 'Project';
export type ScopeIndicator = 'company' | 'project' | 'overrides_company';

export type AssetSource = 'upload' | 'workflow' | 'github';

export interface AssetVersion {
  id: number;
  version: number;
  contentType: string | null;
  fileSize: number | null;
  uploadedById: number;
  source: AssetSource;
  fileUrl: string | null;
  createdAt: string;
}

export interface DetailedAssetVersion extends AssetVersion {
  fileUrl: string | null;
}

export interface Asset {
  id: number;
  name: string;
  folder: string | null;
  tags: string[];
  public: boolean;
  scopeType: ScopeType;
  scopeId: number;
  scopeIndicator: ScopeIndicator;
  createdById: number;
  stepRunId: number | null;
  latestVersion: AssetVersion | null;
  versionsCount: number;
  deletedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface AssetsFilters {
  search?: string;
  folder?: string;
}

export interface CachedFileData {
  id: string;
  storage: string;
}

export interface CreateAssetPayload {
  name: string;
  folder?: string;
  tags?: string[];
  file: CachedFileData;
}

export interface UpdateAssetRequest {
  id: number;
  folder?: string | null;
  tags?: string[];
  public?: boolean;
}
