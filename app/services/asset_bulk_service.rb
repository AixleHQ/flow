# frozen_string_literal: true

# Bulk move / delete for the Assets folder view's multi-select bar, scoped to a Project or
# Company exactly like FolderService. Mirrors TaskService.bulk_action's shape (per-row outcome
# rather than an all-or-nothing transaction — one bad row shouldn't fail the whole batch) and
# Api::V1::Projects::Board::TasksController#bulk_actions' `{ succeeded, skipped }` response.
#
# Scoping is implicit: `@scope.assets` only ever sees this scope's own rows (never a company
# asset viewed from a project, the same boundary FolderService's `own_assets` draws), so an id
# for something outside that boundary is indistinguishable from a missing one — it comes back
# skipped with reason "Not found".
class AssetBulkService
  BULK_ACTIONS = %w[move delete].freeze

  def initialize(scope:, actor:)
    @scope = scope
    @actor = actor
  end

  def call(action:, asset_ids:, folder: nil)
    action = action.to_s
    raise ArgumentError, "Unknown action: #{action}" unless BULK_ACTIONS.include?(action)

    ids = asset_ids.map(&:to_i)
    succeeded = []
    skipped = []

    own_assets.where(id: ids).find_each do |asset|
      ok, reason = send(:"apply_#{action}", asset, folder)
      ok ? succeeded << asset.id : skipped << { id: asset.id, reason: reason }
    end

    (ids - succeeded - skipped.map { |s| s[:id] }).each { |id| skipped << { id: id, reason: "Not found" } }
    { succeeded: succeeded, skipped: skipped }
  end

  private

  def own_assets
    @scope.assets.active
  end

  def apply_move(asset, folder)
    return [ true, nil ] if asset.update(folder: folder.presence)

    [ false, asset.errors.full_messages.to_sentence.presence || "Could not move" ]
  end

  def apply_delete(asset, _folder)
    asset.soft_delete!
    [ true, nil ]
  end
end
