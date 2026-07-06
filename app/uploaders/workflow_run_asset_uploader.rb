# frozen_string_literal: true

class WorkflowRunAssetUploader < Shrine
  plugin :activerecord
  plugin :determine_mime_type, analyzer: :marcel, analyzer_options: { filename_fallback: true }
  plugin :pretty_location
  plugin :restore_cached_data
  plugin :cached_attachment_data
  plugin :validation_helpers

  Attacher.validate do
    validate_max_size 1024 * 1024 * 1024, message: "is too large (max is 1 GB)"
    validate_mime_type %w[
      image/jpeg image/png image/gif image/webp image/svg+xml
      application/pdf text/plain text/csv text/markdown
      application/zip application/json application/octet-stream
      text/x-python text/x-ruby application/javascript
    ]
  end

  def generate_location(io, record: nil, **)
    return super unless record.is_a?(WorkflowRunAsset)

    run_id = record.workflow_run_id
    step_run_id = record.produced_by_step_run_id || "manual"
    filename = super(io).split("/").last

    "workflow_runs/#{run_id}/steps/#{step_run_id}/#{filename}"
  end
end
