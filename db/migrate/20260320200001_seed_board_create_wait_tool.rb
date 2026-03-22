# frozen_string_literal: true

class SeedBoardCreateWaitTool < ActiveRecord::Migration[7.2]
  def up
    Tool.find_or_initialize_by(name: "board_create_wait", kind: "workflow").update!(
      display_name: "Board Create Wait",
      description: "Create a Wait on a board task. The auto-workflow for the task's column will not fire until all Waits are resolved.",
      input_schema: {
        "type" => "object",
        "properties" => {
          "task_id"        => { "type" => "integer", "description" => "Board task ID" },
          "wait_type"      => { "type" => "string",  "description" => "Wait type. Supported: github_checks_completed" },
          "repo_full_name" => { "type" => "string",  "description" => "(github_checks_completed) Full repo name, e.g. owner/repo" },
          "pr_number"      => { "type" => "integer", "description" => "(github_checks_completed) Pull request number" }
        },
        "required" => %w[task_id wait_type]
      },
      execution_mode: "app"
    )
  end

  def down
    Tool.find_by(name: "board_create_wait", kind: "workflow")&.destroy
  end
end
