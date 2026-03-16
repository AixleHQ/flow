# frozen_string_literal: true

class RemoveDefaultsFromNamespaceResourceQuotas < ActiveRecord::Migration[7.2]
  def up
    change_column_default :namespace_resource_quotas, :cpu_limits, from: "4000m", to: nil
    change_column_default :namespace_resource_quotas, :memory_limits, from: "8Gi", to: nil
    change_column_default :namespace_resource_quotas, :max_pods, from: 100, to: nil
  end

  def down
    change_column_default :namespace_resource_quotas, :cpu_limits, from: nil, to: "4000m"
    change_column_default :namespace_resource_quotas, :memory_limits, from: nil, to: "8Gi"
    change_column_default :namespace_resource_quotas, :max_pods, from: nil, to: 100
  end
end
