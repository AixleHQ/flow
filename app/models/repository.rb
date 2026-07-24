# frozen_string_literal: true

class Repository < ApplicationRecord
  belongs_to :scope, polymorphic: true
  belongs_to :integration

  before_validation :set_clone_url, if: -> { clone_url.blank? && full_name.present? && integration.present? }

  validates :full_name, presence: true,
                        format: { with: %r{\A[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)+\z}, message: "must be in owner/repo format (e.g. org/repo or group/subgroup/repo)" }
  validates :full_name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :source_branch, presence: true
  validates :clone_url, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }

  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :for_integration, ->(integration) { where(integration: integration) }

  scope :visible_for_project, ->(project) {
    where(scope_type: "Project", scope_id: project.id)
  }

  # Project ids connected to a repo by full_name. Repositories are Project-scoped,
  # so this maps a repo directly to the projects that registered it. Used to fan
  # an inbound CI webhook out to every project that owns the repo.
  def self.project_ids_for(repo_full_name)
    where(full_name: repo_full_name, scope_type: "Project").pluck(:scope_id).uniq
  end

  def picker_name
    full_name
  end

  def scope_indicator
    "project"
  end

  def repo_name
    full_name&.split("/")&.last
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[full_name source_branch is_private scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope integration]
  end

  private

  def set_clone_url
    base = case integration.provider.to_s
    when "github" then "https://github.com"
    when "gitlab" then "https://gitlab.com"
    end
    self.clone_url = "#{base}/#{full_name}.git" if base
  end
end
