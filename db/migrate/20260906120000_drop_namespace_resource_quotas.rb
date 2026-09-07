# frozen_string_literal: true

# Namespace ResourceQuotas were how concurrency used to be limited: a per-scope
# Kubernetes quota that made an over-capacity launch fail at provisioning with a
# 403. The session admission queue replaces that with a counted, ordered wait,
# and production cut over on 2026-09-05 — the quotas were converted into
# per-scope session limits, the 62 quota objects were deleted from the cluster,
# and the runtime has not written one since.
#
# What is left is a table nobody reads, which is a table someone will edit
# believing it still governs something.
#
# Safe to run only because production is already on the new code: the rows were
# the input to the conversion, so this could not land in the same release that
# introduced the queue.
class DropNamespaceResourceQuotas < ActiveRecord::Migration[8.1]
  def up
    drop_table :namespace_resource_quotas
  end

  def down
    create_table :namespace_resource_quotas do |t|
      t.references :scope, polymorphic: true, null: false
      t.string :cpu_requests
      t.string :memory_requests
      t.string :cpu_limits
      t.string :memory_limits
      t.integer :max_pods
      t.text :description

      t.timestamps
    end

    add_index :namespace_resource_quotas, %i[scope_type scope_id], unique: true
  end
end
