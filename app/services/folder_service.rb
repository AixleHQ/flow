# frozen_string_literal: true

# Creates, relocates (rename/move) and deletes `Folder` rows for a Project or Company's Assets
# folder view, keeping `folders.path` and `assets.folder` consistent with each other.
#
# The visible folder tree a caller sees is the union of persisted `Folder` rows and every path an
# `Asset#folder` references (plus each such path's ancestors) — see `folderTree.ts` on the frontend
# for the same computation. All guard checks here read against that *visible* tree (which, in
# project scope, includes the parent company's folders/assets too) so a collision or missing-parent
# error matches what's on screen; all WRITES only ever touch `@scope`'s own rows.
class FolderService
  class InvalidPathError < StandardError; end
  class CollisionError < StandardError; end

  class NotEmptyError < StandardError
    attr_reader :item_count

    def initialize(item_count)
      @item_count = item_count
      super("Folder is not empty (#{item_count} item#{'s' unless item_count == 1} inside)")
    end
  end

  def initialize(scope:, actor:)
    @scope = scope
    @actor = actor
  end

  def create!(path)
    validate_format!(path)

    parent = folder_parent(path)
    raise InvalidPathError, "Parent folder does not exist." if parent.present? && !folder_path?(parent)

    label = folder_label(path)
    raise CollisionError, "An item named \"#{label}\" already exists in that location." if sibling_collision?(parent, label)

    @scope.folders.create!(path: path, created_by: @actor)
  end

  # Powers both rename (same parent, new label) and move (new parent, same label) — the caller
  # computes `to_path` either way and this cascades `folders.path` + `assets.folder` in one
  # transaction, pre-checking every affected row so a partial cascade can never hit the DB's
  # `(scope, folder, name)` unique index mid-flight.
  def relocate!(from_path:, to_path:)
    return { from: from_path, to: to_path } if from_path == to_path

    validate_format!(to_path)
    raise ActiveRecord::RecordNotFound, "Folder not found: #{from_path}" unless own_path?(from_path)
    if to_path == from_path || to_path.start_with?("#{from_path}/")
      raise InvalidPathError, "Can't move a folder into itself or one of its own subfolders."
    end

    to_parent = folder_parent(to_path)
    raise InvalidPathError, "Destination folder does not exist." if to_parent.present? && !folder_path?(to_parent)

    to_label = folder_label(to_path)
    if sibling_collision?(to_parent, to_label)
      raise CollisionError, "An item named \"#{to_label}\" already exists at the destination."
    end
    raise CollisionError, company_guard_message if company_assets_under?(from_path)

    cut = from_path.length + 1
    ActiveRecord::Base.transaction do
      guard_destination_collisions!(from_path, to_path)

      own_assets.where("folder = :p OR folder LIKE :pre", p: from_path, pre: "#{from_path}/%")
                .update_all([ "folder = CASE WHEN folder = :from THEN :to ELSE :to || substr(folder, :cut) END, " \
                             "updated_at = :now",
                             from: from_path, to: to_path, cut: cut, now: Time.current ])
      own_folders.where("path = :p OR path LIKE :pre", p: from_path, pre: "#{from_path}/%")
                 .update_all([ "path = CASE WHEN path = :from THEN :to ELSE :to || substr(path, :cut) END, " \
                              "updated_at = :now",
                              from: from_path, to: to_path, cut: cut, now: Time.current ])
    end

    { from: from_path, to: to_path }
  rescue ActiveRecord::RecordNotUnique
    raise CollisionError, "That location already has an item with the same name."
  end

  def destroy!(path:, recursive: false)
    folder = find_own_folder!(path)

    if recursive
      raise CollisionError, company_guard_message if company_assets_under?(path)

      deleted_assets = 0
      deleted_folders = 0
      ActiveRecord::Base.transaction do
        deleted_assets = own_assets.where("folder = :p OR folder LIKE :pre", p: path, pre: "#{path}/%")
                                    .update_all(deleted_at: Time.current, updated_at: Time.current)
        deleted_folders = own_folders.where("path = :p OR path LIKE :pre", p: path, pre: "#{path}/%")
                                      .delete_all
      end
      { path: path, deleted_assets: deleted_assets, deleted_folders: deleted_folders }
    else
      raise NotEmptyError, direct_item_count(path) unless folder.empty?

      folder.destroy!
      { path: path, deleted_assets: 0, deleted_folders: 0 }
    end
  end

  private

  def validate_format!(path)
    return if path.present? && Folder::PATH_FORMAT.match?(path)

    raise InvalidPathError, "Folder name must contain only letters, digits, hyphens or underscores."
  end

  def find_own_folder!(path)
    own_folders.find_by(path: path) || raise(ActiveRecord::RecordNotFound, "Folder not found: #{path}")
  end

  # Whether `path` refers to something of this scope's own — a persisted Folder row there or a
  # descendant of it, or an own Asset directly in it or nested under it (a purely derived folder
  # has no Folder row but is still "there" as long as this scope's own assets populate it).
  def own_path?(path)
    own_folders.exists?(path: path) ||
      own_assets.where("folder = :p OR folder LIKE :pre", p: path, pre: "#{path}/%").exists?
  end

  def own_folders
    @scope.folders
  end

  def own_assets
    @scope.assets.active
  end

  def project?
    @scope.is_a?(Project)
  end

  def visible_folders
    project? ? Folder.accessible_from_project(@scope) : Folder.for_company(@scope)
  end

  def visible_assets
    project? ? Asset.accessible_from_project(@scope) : Asset.for_company(@scope)
  end

  # Recomputed on every call, deliberately not memoized: a single service instance may run
  # several mutating calls in a row (e.g. a bulk move), and each must see the previous call's
  # writes rather than a snapshot taken before them.
  def all_folder_paths
    paths = visible_folders.pluck(:path).to_set
    visible_assets.distinct.pluck(:folder).each { |folder| add_ancestors!(paths, folder) if folder.present? }
    paths
  end

  def add_ancestors!(set, path)
    current = path
    current = folder_parent(current) while current.present? && set.add?(current)
  end

  def folder_path?(path)
    all_folder_paths.include?(path)
  end

  def folder_parent(path)
    path.include?("/") ? path.rpartition("/").first : nil
  end

  def folder_label(path)
    path.include?("/") ? path.rpartition("/").last : path
  end

  def sibling_collision?(parent_path, label)
    sibling_folder_labels = all_folder_paths.select { |p| folder_parent(p) == parent_path }.map { |p| folder_label(p) }
    return true if sibling_folder_labels.include?(label)

    visible_assets.where(folder: parent_path, name: label).exists?
  end

  def company_assets_under?(path)
    return false unless project?

    visible_assets.where(scope_type: "Company")
                  .where("folder = :p OR folder LIKE :pre", p: path, pre: "#{path}/%")
                  .exists?
  end

  def company_guard_message
    "This folder contains company-managed files that can't be changed from a project."
  end

  def relocate_value(value, from_path, to_path)
    value == from_path ? to_path : to_path + value[from_path.length..]
  end

  # Re-checked inside the transaction: the two guards above only rule out a collision at the top
  # of the moved subtree — this catches the narrower case where a *nested* descendant's computed
  # destination lands on an existing name a few levels down.
  def guard_destination_collisions!(from_path, to_path)
    own_assets.where("folder = :p OR folder LIKE :pre", p: from_path, pre: "#{from_path}/%").find_each do |asset|
      new_folder = relocate_value(asset.folder, from_path, to_path)
      if own_assets.where(folder: new_folder, name: asset.name).where.not(id: asset.id).exists?
        raise CollisionError, "\"#{asset.name}\" already exists at the destination."
      end
    end

    own_folders.where("path = :p OR path LIKE :pre", p: from_path, pre: "#{from_path}/%").find_each do |folder|
      new_path = relocate_value(folder.path, from_path, to_path)
      if own_folders.where(path: new_path).where.not(id: folder.id).exists?
        raise CollisionError, "A folder already exists at the destination."
      end
    end
  end

  def direct_item_count(path)
    child_folders = own_folders.to_a.count { |f| f.parent_path == path }
    child_files = own_assets.where(folder: path).count
    child_folders + child_files
  end
end
