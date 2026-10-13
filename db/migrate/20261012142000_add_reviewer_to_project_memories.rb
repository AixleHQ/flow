# frozen_string_literal: true

class AddReviewerToProjectMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :project_memories, :base_revision, :uuid
    add_reference :project_memories, :validated_by, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
