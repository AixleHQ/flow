class RemoveUniquePositionIndexFromSubSteps < ActiveRecord::Migration[8.0]
  def change
    remove_index :sub_steps, [:step_id, :position], unique: true, name: "index_sub_steps_on_step_id_and_position"
    add_index :sub_steps, [:step_id, :position], name: "index_sub_steps_on_step_id_and_position"
  end
end
