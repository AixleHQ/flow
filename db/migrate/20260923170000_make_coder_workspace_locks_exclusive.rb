# frozen_string_literal: true

# A Coder workspace is one machine, whichever integration reaches it. Two
# integrations on one pool each took their own lock on the same box and handed it
# to sessions of different tenants; the workspace id (a UUID) is now unique across
# every live lock row.
class MakeCoderWorkspaceLocksExclusive < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX = "index_integration_data_on_coder_workspace_lock"

  def up
    execute <<~SQL.squish
      DELETE FROM integration_data
      WHERE key LIKE 'coder:workspace_lock:%' AND expires_at IS NOT NULL AND expires_at <= now()
    SQL
    # A box held twice right now keeps its first holder.
    execute <<~SQL.squish
      DELETE FROM integration_data later USING integration_data earlier
      WHERE later.key LIKE 'coder:workspace_lock:%' AND earlier.key LIKE 'coder:workspace_lock:%'
        AND later.value ->> 'workspace_id' = earlier.value ->> 'workspace_id'
        AND (later.created_at, later.id) > (earlier.created_at, earlier.id)
    SQL
    add_index :integration_data, "(value ->> 'workspace_id')", unique: true, name: INDEX,
              where: "key LIKE 'coder:workspace_lock:%'", algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :integration_data, name: INDEX, algorithm: :concurrently, if_exists: true
  end
end
