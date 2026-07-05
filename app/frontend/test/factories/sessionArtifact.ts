import type SessionArtifact from '@/types/generated/SessionArtifact';

// The `: SessionArtifact` return annotation is the compile-time drift contract: if Typelizer
// regenerates SessionArtifact with a changed/added required field, this factory stops compiling.
export const buildSessionArtifact = (overrides: Partial<SessionArtifact> = {}): SessionArtifact => ({
  id: 1,
  name: 'report.pdf',
  folder: null,
  status: 'pending',
  createdAt: '2026-01-01T00:00:00Z',
  // optional (?) attributes — realistic values, no compile-time guarantee.
  // downloadUrl is `string | undefined` (not nullable): omit/override with undefined for "absent".
  fileSize: 2048,
  contentType: 'application/pdf',
  downloadUrl: 'https://example.com/report.pdf',
  ...overrides,
});
