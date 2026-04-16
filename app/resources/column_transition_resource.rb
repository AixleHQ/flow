# frozen_string_literal: true

class ColumnTransitionResource < ApplicationResource
  attributes :id, :board_task_id, :from_column_id, :to_column_id,
             :actor_id, :actor_type, :workflow_run_id, :created_at
end
