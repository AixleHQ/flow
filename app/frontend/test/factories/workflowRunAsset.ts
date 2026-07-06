import type WorkflowRunAsset from '@/types/generated/WorkflowRunAsset';

// The `: WorkflowRunAsset` return annotation is the compile-time drift contract: if Typelizer
// regenerates WorkflowRunAsset with a changed/added required field, this factory stops compiling.
export const buildWorkflowRunAsset = (overrides: Partial<WorkflowRunAsset> = {}): WorkflowRunAsset => ({
  id: 11,
  name: 'report.pdf',
  workflowRunId: 42,
  producedByStepRunId: null,
  s3Key: null,
  createdAt: '2026-01-01T00:00:00Z',
  contentType: 'application/pdf',
  fileSize: 2048,
  // optional (?) computed attributes — realistic values, no compile-time guarantee
  stepName: 'Compile Specs',
  downloadUrl: 'https://files.example.com/report.pdf',
  ...overrides,
});
