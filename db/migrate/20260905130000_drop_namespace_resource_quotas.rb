# frozen_string_literal: true

# Namespace ResourceQuotas were how concurrency used to be limited: a per-scope
# Kubernetes quota that made an over-capacity launch fail at provisioning. The
# session admission queue replaces that with a counted, ordered wait, so these
# rows no longer govern anything — the runtime stopped writing quota objects
# with the queue's arrival, and a table nobody reads is a table that will be
# edited by someone who believes it still works.
#
# The Kubernetes objects themselves are a separate cleanup, performed once
# against a reviewed UID allowlist: `session_admission:remove_legacy_quotas`.
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
