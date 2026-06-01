# frozen_string_literal: true

class WorkflowTemplateVersion < ApplicationRecord
  belongs_to :workflow_template, inverse_of: :versions
  belongs_to :workflow
  belongs_to :published_by, class_name: "User"
  belongs_to :source_workflow, class_name: "Workflow", optional: true

  has_many :projects, dependent: :nullify

  validates :version_number, presence: true, uniqueness: { scope: :workflow_template_id }
  validates :published_at, presence: true

  scope :latest_first, -> { order(version_number: :desc) }

  def self.next_version_number(template)
    (template.versions.maximum(:version_number) || 0) + 1
  end
end
