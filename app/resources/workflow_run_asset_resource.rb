# frozen_string_literal: true

class WorkflowRunAssetResource < ApplicationResource
  attributes :id, :name, :workflow_run_id, :produced_by_step_run_id,
             :s3_key, :created_at

  attribute :content_type do |wra|
    wra.file&.mime_type
  end

  attribute :file_size do |wra|
    wra.file&.size
  end

  attribute :step_name do |wra|
    wra.produced_by_step_run&.step&.name
  end

  attribute :download_url do |wra|
    next nil unless wra.file.present?

    download_api_v1_project_workflow_run_workflow_run_asset_path(
      project_id: wra.workflow_run.project_id,
      workflow_run_id: wra.workflow_run_id,
      id: wra.id
    )
  end
end
