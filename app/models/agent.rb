# frozen_string_literal: true

# Agent — LLM persona configuration, independent of workflows
# Can be used in standalone sessions or workflow steps
#
# Stores only data for the system prompt (persona fields).
# Does NOT store activation/menu — that is BMAD-specific runtime logic.
class Agent < ApplicationRecord
  extend Enumerize

  # Polymorphic scope (Company or Project)
  belongs_to :scope, polymorphic: true

  # Source: custom (created in UI) or bmad_import (imported from BMAD files)
  enumerize :source, in: %i[custom bmad_import], default: :custom, predicates: true

  # Auto-downcase name
  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_]/, "_"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must start with letter, use lowercase letters, numbers, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :title, presence: true
  validates :persona, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true

  # Scopes
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  scope :visible_for_project, ->(project) {
    where(scope_type: "Company", scope_id: project.company_id)
      .or(where(scope_type: "Project", scope_id: project.id))
  }
  scope :belonging_to_company, ->(company) {
    where(scope_type: "Company", scope_id: company.id)
      .or(where(scope_type: "Project", scope_id: company.project_ids))
  }

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name title source scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end

  # Build system prompt from persona fields
  def to_system_prompt
    parts = []
    parts << "# #{title}" if title.present?
    parts << persona if persona.present?
    parts << "\n## Communication Style\n#{communication_style}" if communication_style.present?
    parts << "\n## Principles\n#{principles}" if principles.present?
    parts.join("\n\n")
  end
end
