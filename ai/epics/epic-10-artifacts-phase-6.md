# Epic 10: Artifacts (Phase 6)

Users can upload, view, and manage artifacts.

**FRs covered:** FR19, FR20, FR21, FR22, FR23, FR24, FR25

**Phase:** 6 (Depends on: Epic 9 Sessions)

**User Outcome:** Complete artifact management with versioning and provenance.

## Story 10.1: Upload Assets to Project

**Acceptance Criteria:**
- Upload files to S3
- Metadata saved to database
- Progress indicator
- Supports documents, images, archives, code

## Story 10.2: View Artifacts List

**Acceptance Criteria:**
- List all project artifacts
- Shows name, size, date, uploader, provenance
- Search and filter
- Grid/list view toggle

## Story 10.3: Download Artifacts

**Acceptance Criteria:**
- Download from S3
- Preserves original filename
- Bulk download support

## Story 10.4: Delete Artifacts

**Acceptance Criteria:**
- Soft delete with confirmation
- Can restore within retention period
- Warning if referenced by workflow

## Story 10.5: S3 Storage Integration

**Acceptance Criteria:**
- Files stored in S3 bucket
- Path: projects/{id}/artifacts/{id}/{filename}
- Encrypted at rest
- Access restricted to authenticated requests

## Story 10.6: Artifact History & Versioning

**Acceptance Criteria:**
- New version on same filename upload
- Version numbers (v1, v2, v3)
- Can view/download any version
- Version history shows metadata

## Story 10.7: Artifact Provenance Tracking

**Acceptance Criteria:**
- Manual upload: "Upload by {user} on {date}"
- Workflow: "Workflow '{name}' → Step '{step}' by {user}"
- Provenance displayed everywhere
- Can navigate to workflow run

---
