# frozen_string_literal: true

class RemoveConfiguredAgentsFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :configured_agents, :text, array: true, default: []
  end
end
