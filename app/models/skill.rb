# frozen_string_literal: true

# Skill — registry-based agent skill from skills.sh ecosystem
#
# Skills are discovered via skills.sh API search and registered in the database.
# Actual installation into agent containers is handled by `npx skills add`
# at session start (see SessionContextService#inject_skills).
#
# scope: Project only (polymorphic)
# package: "owner/repo@skill-name" (unique identifier in skills.sh)
# source: "owner/repo" (GitHub repository)
# content: SKILL.md content (used for title/description extraction and context summary)
class Skill < ApplicationRecord
  belongs_to :scope, polymorphic: true

  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_:-]*\z/, message: "must start with letter, use lowercase letters, numbers, underscores, hyphens, colons" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :package, presence: true
  validates :source, presence: true
  validates :content, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }
  validates :scope_id, presence: true

  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :visible_for_project, ->(project) { for_project(project) }

  def name=(val)
    super(val&.downcase&.gsub(/[^a-z0-9_:-]/, "_"))
  end

  def picker_name
    title.presence || name
  end

  def scope_indicator
    "project"
  end

  def registry_url
    "https://skills.sh/#{source}/#{name}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name title package source scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end
end
