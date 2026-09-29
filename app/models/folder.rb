# frozen_string_literal: true

# A folder is a navigable container for `Asset`s, scoped to a Project or a Company exactly like
# `Asset` itself. There is no `parent_id` — a folder's parent, label, and depth are all derived
# from `path` (the same shape `Asset#folder` already uses), so a rename/move is a pure string
# cascade over both `folders.path` and `assets.folder` (see `FolderService`).
#
# A folder can also exist purely *derived* — with no row here at all — when an `Asset#folder`
# value references a path nobody explicitly created. Those show in the Assets folder view too
# (the tree is the union of persisted rows and asset paths, computed in the frontend from both
# props), but they can never be deleted because they can never be empty.
class Folder < ApplicationRecord
  belongs_to :scope, polymorphic: true
  include TenantColumns
  # Optional so a folder outlives the user who created it — permanent user
  # deletion nullifies the column (see NullifyFoldersCreatedByFk).
  belongs_to :created_by, class_name: "User", optional: true

  # A segment is free-form on purpose. Asset folders have always been labels a human types —
  # spaces and non-Latin scripts included — and narrowing that to `[a-zA-Z0-9_-]` would strand
  # every folder already named that way: reads would still work, but `update!` runs validations,
  # so the row could no longer be moved, promoted or even soft-deleted. What a segment may NOT
  # hold is a separator or a control character: `/` and `\` would let it address a directory of
  # its own choosing under /workspace/assets, and a control character would make the directory
  # unnameable at the far end. Everything that consumes the path shell-escapes it.
  SEGMENT_FORMAT = /[^\/\\\x00-\x1F\x7F]+/
  PATH_FORMAT = /\A#{SEGMENT_FORMAT}(\/#{SEGMENT_FORMAT})*\z/
  # These pass the format but name a directory that already exists — and ".." names the parent,
  # which walks the path out of the assets directory entirely.
  RESERVED_SEGMENTS = %w[. ..].freeze
  PATH_MESSAGE = "must be one or more segments separated by /, with no backslashes or control " \
                 "characters, and no segment blank, \".\" or \"..\""

  # Canonical form of a path: every segment trimmed, blank meaning "no path" (nil). Every write
  # and every lookup has to agree on it, or "docs" and "docs " are two folders that render
  # identically and neither can be told from the other. It is per segment rather than one outer
  # strip because nesting puts segments where an outer strip can't reach — " a / b " is "a/b".
  # A segment that was only whitespace collapses to empty, which PATH_FORMAT then rejects.
  def self.normalize_path(value)
    return value.presence unless value.is_a?(String)

    # split("/", -1) keeps trailing empties, so "a/" stays "a/" and is still rejected.
    value.split("/", -1).map(&:strip).join("/").presence
  end

  # The path rules as one predicate, so Asset, FolderService and the agent tools all reject the
  # same strings. A blank path is not a valid path here; whether blank is acceptable at all is
  # the caller's question (for Asset it means "root").
  def self.invalid_path?(path)
    return true unless path.is_a?(String) && path.match?(PATH_FORMAT)

    path.split("/").any? { |segment| segment.strip.empty? || RESERVED_SEGMENTS.include?(segment) }
  end

  before_validation :normalize_path
  validates :path, presence: true
  validate :path_shape
  validates :path, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :scope_type, presence: true, inclusion: { in: %w[Company Project] }
  validates :scope_id, presence: true

  scope :for_company, ->(company) { where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :accessible_from_project, ->(project) {
    for_project(project).or(where(scope_type: "Company", scope_id: project.company_id))
  }

  def label
    path.include?("/") ? path.rpartition("/").last : path
  end

  def parent_path
    path.include?("/") ? path.rpartition("/").first : nil
  end

  def depth
    path.count("/")
  end

  # Every ancestor path, nearest first — e.g. `"a/b/c"` -> `["a/b", "a"]`.
  def ancestor_paths
    paths = []
    current = parent_path
    while current
      paths << current
      current = current.include?("/") ? current.rpartition("/").first : nil
    end
    paths
  end

  def scope_indicator
    scope_type == "Company" ? "company" : "project"
  end

  def descendant_folder_scope
    self.class.where(scope_type: scope_type, scope_id: scope_id).where("path LIKE ?", subtree_pattern)
  end

  def descendant_asset_scope
    Asset.active.where(scope_type: scope_type, scope_id: scope_id)
         .where("folder = :path OR folder LIKE :prefix", path: path, prefix: subtree_pattern)
  end

  def empty?
    descendant_folder_scope.none? && descendant_asset_scope.none?
  end

  # The path's own LIKE wildcards are literal (see FolderService#subtree_pattern).
  def subtree_pattern
    "#{self.class.sanitize_sql_like(path)}/%"
  end

  private

  def normalize_path
    self.path = self.class.normalize_path(path)
  end

  def path_shape
    # `presence` already speaks for a blank path; adding a shape error too would say it twice.
    return if path.blank?

    errors.add(:path, PATH_MESSAGE) if self.class.invalid_path?(path)
  end
end
