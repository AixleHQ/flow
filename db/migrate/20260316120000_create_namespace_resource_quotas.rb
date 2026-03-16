# frozen_string_literal: true

class CreateNamespaceResourceQuotas < ActiveRecord::Migration[7.2]
  def change
    create_table :namespace_resource_quotas do |t|
      t.references :scope, polymorphic: true, null: false
      t.string :cpu_requests
      t.string :memory_requests
      t.string :cpu_limits, default: "4000m"
      t.string :memory_limits, default: "8Gi"
      t.integer :max_pods, default: 100
      t.text :description

      t.timestamps
    end

    add_index :namespace_resource_quotas, %i[scope_type scope_id], unique: true
  end
end
