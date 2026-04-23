# frozen_string_literal: true

class TaskDetailResource < BoardTaskResource
  attribute :description do |task|
    task.description
  end

  attribute :assets_count do |task|
    task.task_assets.size
  end
end
