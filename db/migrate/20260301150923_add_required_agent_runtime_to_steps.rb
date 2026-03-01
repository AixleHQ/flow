class AddRequiredAgentRuntimeToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :required_agent_runtime, :string
  end
end
