# frozen_string_literal: true

# Skill — an agent skill available to a project, either installed from skills.sh
# or written by hand.
#
# Registry skills are discovered via the public skills.sh search endpoint and
# installed into agent containers by `npx skills add` at session start (see
# SessionContextService#inject_skills). Manual skills never touch the CLI: their
# directory is written into the container directly, because every CLI install
# reports an event upstream naming the skill and the path it landed at, and a
# hand-written skill is nobody else's business.
#
# scope: Project only (polymorphic)
# package: "owner/repo@skill-name" (unique identifier in skills.sh) — registry only
# source: "owner/repo" (GitHub repository) — registry only
# content: SKILL.md content (used for title/description extraction and context summary)
# content_hash: registry digest from the download endpoint, for update detection
# files: the skill directory as installed ({ relative path => contents }) — what a
#        session writes into the container, so it runs the release that was installed
#        rather than whatever upstream holds today. Empty on rows installed before it
#        existed; those still go through `npx skills add` until `skills:snapshot`.
class Skill < ApplicationRecord
  extend Enumerize

  belongs_to :scope, polymorphic: true
  include TenantColumns

  # Where the row came from. Everything conditional about a skill keys off this
  # rather than off which columns happen to be filled in.
  enumerize :origin, in: %i[registry manual], default: :registry, predicates: true, scope: true

  # The Agent Skills spec is strict: 1–64 chars, lowercase alphanumerics and
  # hyphens, no leading/trailing hyphen, no doubled hyphen, and the name MUST equal
  # the skill's directory name. We can enforce that for skills authored here.
  MANUAL_NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  # Registry names are upstream's, and they are what gets passed to
  # `skills add --skill <name>`. Normalizing them to spec shape would break the
  # install, so they are accepted as published — only obvious junk is rejected.
  REGISTRY_NAME_FORMAT = /\A[a-z0-9][a-z0-9_.:-]*\z/
  NAME_MAX_LENGTH = 64

  validates :name, presence: true
  # Length and format are checked only when the name is being set, so a legacy row
  # whose name predates these rules can still be saved for unrelated reasons.
  validates :name, length: { maximum: NAME_MAX_LENGTH }, if: :name_changed?
  validates :name,
            format: {
              with: MANUAL_NAME_FORMAT,
              message: "must be lowercase letters, numbers and single hyphens (Agent Skills spec)"
            },
            if: -> { manual? && name_changed? }
  validates :name,
            format: {
              with: REGISTRY_NAME_FORMAT,
              message: "must start with a letter or number and use lowercase letters, numbers, . _ : -"
            },
            if: -> { !manual? && name_changed? }
  validates :name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :package, presence: true, unless: :manual?
  validates :source, presence: true, unless: :manual?
  validates :content, presence: true
  validates :origin, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }
  validates :scope_id, presence: true

  # A skill directory is instructions plus the odd script; far below these.
  MAX_FILES = 200
  MAX_BUNDLE_BYTES = 2 * 1024 * 1024

  # The skill directory from a registry bundle ([{ "path", "contents" }]): paths made
  # relative to the directory holding SKILL.md, and anything that could land outside
  # it refused. nil when the bundle is unusable, so the caller keeps its fallback.
  def self.files_from_bundle(entries)
    entries = Array(entries).select { |e| e.is_a?(Hash) && e["path"].is_a?(String) && e["contents"].is_a?(String) }
    skill_md = entries.find { |e| e["path"] == "SKILL.md" || e["path"].end_with?("/SKILL.md") }
    return nil unless skill_md

    root = skill_md["path"].delete_suffix("SKILL.md")
    files = entries.filter_map do |entry|
      next unless entry["path"].start_with?(root)

      [ entry["path"].delete_prefix(root), entry["contents"] ]
    end.to_h
    return nil unless files.size <= MAX_FILES && files.sum { |_, c| c.bytesize } <= MAX_BUNDLE_BYTES
    return nil unless files.keys.all? { |path| safe_relative_path?(path) }

    files
  end

  def self.safe_relative_path?(path)
    path.present? && !path.start_with?("/", "~") && !path.include?("\\") && !path.include?("\0") &&
      path.split("/").none? { |part| part.empty? || part == "." || part == ".." }
  end

  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :visible_for_project, ->(project) { for_project(project) }

  def name=(val)
    super(val&.to_s&.strip&.downcase)
  end

  def picker_name
    title.presence || name
  end

  def scope_indicator
    "project"
  end

  # A hand-written skill has no registry page to link to.
  def registry_url
    return nil if manual?

    "https://skills.sh/#{source}/#{name}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name title package source origin scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope]
  end
end
