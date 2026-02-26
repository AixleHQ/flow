# frozen_string_literal: true

class WorkflowRunAssetSerializer < ApplicationSerializer
  attributes :id, :workflow_run_id, :produced_by_step_run_id,
             :name, :s3_key, :content_type, :file_size,
             :created_at, :download_url

  def download_url
    object.file&.url
  end
end
