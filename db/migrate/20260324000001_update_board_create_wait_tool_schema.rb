# frozen_string_literal: true

class UpdateBoardCreateWaitToolSchema < ActiveRecord::Migration[8.0]
  NEW_SCHEMA = {
    type: "object",
    properties: {
      task_id:        { type: "integer", description: "Board task ID" },
      wait_type:      { type: "string",  description: "Wait type. Supported: github_checks_completed, github_workflow_completed" },
      repo_full_name: { type: "string",  description: "(github_checks_completed, github_workflow_completed) Full repo name, e.g. owner/repo" },
      pr_number:      { type: "integer", description: "(github_checks_completed) Pull request number" },
      run_id:         { type: "integer", description: "(github_workflow_completed) GitHub Actions workflow run ID" }
    },
    required: %w[task_id wait_type]
  }.freeze

  OLD_SCHEMA = {
    type: "object",
    properties: {
      task_id:        { type: "integer", description: "Board task ID" },
      wait_type:      { type: "string",  description: "Wait type. Supported: github_checks_completed" },
      repo_full_name: { type: "string",  description: "(github_checks_completed) Full repo name, e.g. owner/repo" },
      pr_number:      { type: "integer", description: "(github_checks_completed) Pull request number" }
    },
    required: %w[task_id wait_type]
  }.freeze

  def up
    tool = Tool.find_by(name: "board_create_wait")
    return unless tool

    tool.update!(input_schema: NEW_SCHEMA)
  end

  def down
    tool = Tool.find_by(name: "board_create_wait")
    return unless tool

    tool.update!(input_schema: OLD_SCHEMA)
  end
end
