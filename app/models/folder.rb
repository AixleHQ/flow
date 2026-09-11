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
  belongs_to :created_by, class_name: "User"

  PATH_FORMAT = /\A[a-zA-Z0-9_-]+(\/[a-zA-Z0-9_-]+)*\z/

  validates :path, presence: true, format: { with: PATH_FORMAT,
                                              message: "must be one or more path segments of letters, " \
                                                       "digits, hyphens or underscores, separated by /" }
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
    self.class.where(scope_type: scope_type, scope_id: scope_id).where("path LIKE ?", "#{path}/%")
  end

  def descendant_asset_scope
    Asset.active.where(scope_type: scope_type, scope_id: scope_id)
         .where("folder = :path OR folder LIKE :prefix", path: path, prefix: "#{path}/%")
  end

  def empty?
    descendant_folder_scope.none? && descendant_asset_scope.none?
  end
end
