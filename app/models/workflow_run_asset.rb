# frozen_string_literal: true

class WorkflowRunAsset < ApplicationRecord
  include WorkflowRunAssetUploader::Attachment(:file)

  belongs_to :workflow_run
  belongs_to :produced_by_step_run, class_name: "StepRun", optional: true, inverse_of: :produced_workflow_run_assets

  validates :name, presence: true

  scope :by_step_run, ->(step_run_id) { where(produced_by_step_run_id: step_run_id) }

  def download_to(dir)
    return unless file

    target = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(target))
    file.download { |tempfile| FileUtils.cp(tempfile.path, target) }
    target
  end
end
