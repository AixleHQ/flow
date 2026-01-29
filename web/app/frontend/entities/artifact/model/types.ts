export interface IArtifact {
  id: string;
  name: string;
  type: string;
  mimeType?: string;
  size?: number;
  url?: string;
  workflowRunId?: string;
  workflowName?: string;
  stepId?: string;
  stepName?: string;
  userId?: string;
  userName?: string;
  createdAt: string;
}

export type ArtifactType = 'document' | 'code' | 'image' | 'data' | 'other';

export const getArtifactType = (mimeType?: string, name?: string): ArtifactType => {
  if (!mimeType && !name) return 'other';

  const type = mimeType?.toLowerCase() || '';
  const extension = name?.split('.').pop()?.toLowerCase() || '';

  // Images
  if (type.startsWith('image/') || ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp'].includes(extension)) {
    return 'image';
  }

  // Code
  if (
    ['ts', 'tsx', 'js', 'jsx', 'py', 'rb', 'go', 'rs', 'java', 'c', 'cpp', 'h', 'css', 'scss', 'html'].includes(
      extension,
    ) ||
    type.includes('javascript') ||
    type.includes('typescript')
  ) {
    return 'code';
  }

  // Documents
  if (['md', 'txt', 'pdf', 'doc', 'docx'].includes(extension) || type.includes('text/') || type.includes('pdf')) {
    return 'document';
  }

  // Data
  if (['json', 'yaml', 'yml', 'xml', 'csv'].includes(extension) || type.includes('json') || type.includes('xml')) {
    return 'data';
  }

  return 'other';
};
