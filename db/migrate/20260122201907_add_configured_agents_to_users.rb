class AddConfiguredAgentsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :configured_agents, :text, array: true, default: []
  end
end
