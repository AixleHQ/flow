export interface AssetVersion {
  id: number;
  version: number;
  contentType: string | null;
  fileSize: number | null;
  source: string | null;
  fileUrl: string | null;
  createdAt: string | null;
}

export interface Asset {
  id: number;
  name: string;
  folder: string | null;
  tags: string[];
  public: boolean;
  scopeType: string;
  scopeId: number;
  scopeIndicator: 'company' | 'project';
  status: string;
  createdById: number;
  createdByName: string | null;
  versionsCount: number;
  latestVersion: AssetVersion | null;
  createdAt: string;
  updatedAt: string;
}
