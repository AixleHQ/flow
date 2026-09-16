# frozen_string_literal: true

# Asset folders are now canonicalized on write (Asset.normalize_folder): trimmed, with blank
# meaning "root" (NULL). Uploads look a folder up by exact string, so a legacy row stored as ""
# or with padding would never be matched again — and "" collides with NULL under
# index_assets_on_scope_folder_name (it keys on COALESCE(folder, '')), so the miss surfaces as a
# unique violation rather than a second row.
#
# Conservative by construction: a row whose normalized folder is already taken by a live sibling
# is left exactly as it is — it keeps working the way it does today, and the collision is
# reported instead of failing the deploy.
#
# Idempotent: after the pass every folder is already in canonical form, so a re-run matches
# nothing.
class NormalizeAssetFolders < ActiveRecord::Migration[8.1]
  class MigAsset < ActiveRecord::Base
    self.table_name = "assets"
  end

  def up
    MigAsset.where.not(folder: nil).find_each do |asset|
      normalized = asset.folder.strip.presence
      next if normalized == asset.folder

      begin
        asset.update_columns(folder: normalized)
      rescue ActiveRecord::RecordNotUnique
        say "Asset ##{asset.id}: #{normalized.inspect} is already taken in this scope, left as-is"
      end
    end
  end

  # Not reversible: the original padding is recorded nowhere, and restoring it would put the rows
  # back into the unreachable state this migration exists to clear.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
