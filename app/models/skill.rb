# frozen_string_literal: true

# Skill — reusable domain-specific instructions for AI agent sessions
#
# kind: internal | custom
# - internal: system-provided by Palad, no scope
# - custom: user-created skills with scope (Company or Project)
#
# scope: Company | Project (polymorphic, null for internal)
class Skill < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true

  # Polymorphic scope (Company or Project, null for internal)
  belongs_to :scope, polymorphic: true, optional: true

  # Auto-normalize name (downcase, replace non-alphanumeric with underscore, allow hyphens)
  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_-]/, "_"))
  end

  # Validations
  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "must start with letter, use lowercase letters, numbers, underscores, hyphens" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :kind, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }, if: :custom?
  validates :scope_id, presence: true, if: :custom?
  validates :title, presence: true, if: :custom?
  validates :content, presence: true, if: :custom?

  # Scopes
  scope :internal_skills, -> { where(kind: "internal") }
  scope :custom_skills, -> { where(kind: "custom") }
  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :visible_for_company, ->(company) { internal_skills.or(for_company(company)) }
  scope :visible_for_project, ->(project) { internal_skills.or(for_company(project.company)).or(for_project(project)) }

  # Get merged list of skills for a project (internal + company + project)
  # Returns array with scope_indicator method on each skill
  def self.merged_for_project(project)
    internals = internal_skills.to_a
    company_items = for_company(project.company).to_a
    project_items = for_project(project).to_a
    project_names = project_items.map(&:name).to_set

    internals.each { |i| i.define_singleton_method(:scope_indicator) { "internal" } }

    company_items.each do |item|
      item.define_singleton_method(:scope_indicator) { "company" }
    end

    project_items.each do |item|
      indicator = company_items.any? { |c| c.name == item.name } ? "overrides_company" : "project"
      item.define_singleton_method(:scope_indicator) { indicator }
    end

    merged = internals + project_items + company_items.reject { |c| project_names.include?(c.name) }
    merged.sort_by(&:name)
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[name title kind scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end
end
