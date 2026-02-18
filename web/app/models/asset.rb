# frozen_string_literal: true

class Asset < ApplicationRecord
  extend Enumerize
  belongs_to :scope, polymorphic: true
  belongs_to :created_by, class_name: "User"
  belongs_to :step_run, optional: true

  has_many :versions, class_name: "AssetVersion", dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[scope_type scope_id folder], message: "already exists in this scope" }
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true
  validates :folder, format: { with: /\A[a-z0-9_-]+\z/, message: "only lowercase letters, numbers, hyphens, underscores" },
                     allow_blank: true

  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }

  def self.merged_for_project(project)
    company_items = for_company(project.company).to_a
    project_items = for_project(project).to_a
    project_names = project_items.map(&:name).to_set

    company_items.each do |item|
      item.define_singleton_method(:scope_indicator) { "company" }
    end

    project_items.each do |item|
      indicator = company_items.any? { |c| c.name == item.name } ? "overrides_company" : "project"
      item.define_singleton_method(:scope_indicator) { indicator }
    end

    merged = project_items + company_items.reject { |c| project_names.include?(c.name) }
    merged.sort_by(&:name)
  end

  def latest_version
    versions.order(version: :desc).first
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name folder scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope created_by]
  end
end
