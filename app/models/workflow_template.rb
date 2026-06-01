# frozen_string_literal: true

class WorkflowTemplate < ApplicationRecord
  extend Enumerize

  VISIBILITIES = %w[company private].freeze

  belongs_to :company
  belongs_to :owner, class_name: "User"
  belongs_to :current_version, class_name: "WorkflowTemplateVersion", optional: true

  has_many :versions, class_name: "WorkflowTemplateVersion", dependent: :destroy, inverse_of: :workflow_template
  has_many :projects, through: :versions

  enumerize :visibility, in: VISIBILITIES, default: :company, predicates: true, scope: true

  validates :name, presence: true
  validates :name, uniqueness: { scope: :company_id }

  scope :active, -> { where(archived_at: nil) }
  scope :visible_to, ->(user, company) {
    active.where(company: company).where(
      "workflow_templates.visibility = 'company' OR workflow_templates.owner_id = ?",
      user.id
    )
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name description use_case visibility created_at updated_at]
  end

  def projects_count
    if has_attribute?(:projects_count)
      self[:projects_count].to_i
    else
      Project.where(workflow_template_version_id: versions.select(:id)).count
    end
  end
end
