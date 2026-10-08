# frozen_string_literal: true

# The tool reconciler used to revive a retired code tool without re-enabling it,
# so a row an old process retired mid rolling deploy (the 20261007090000 renames)
# came back live but disabled, and no session got it. No app path disables a code
# tool, so every live disabled one is such a leftover.
class ReenableRevivedCodeTools < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE tools SET enabled = TRUE, updated_at = NOW()
      WHERE source = 'code' AND deleted_at IS NULL AND enabled = FALSE
    SQL
  end

  def down; end
end
