# frozen_string_literal: true

class WorkflowResource < ApplicationResource
  typelize config: "Record<string, unknown>"
  attributes :id, :name, :description, :config, :scope_type, :scope_id, :published_at, :created_at, :updated_at

  typelize %w[system company project]
  attribute :scope_indicator do |workflow|
    workflow.scope_indicator
  end

  typelize :number
  attribute :steps_count do |workflow|
    workflow.steps.select { |s| s.deleted_at.nil? }.size
  end

  typelize :string?
  attribute :last_run_at do |workflow|
    workflow.runs.max_by(&:created_at)&.created_at
  end

  typelize :string?
  attribute :last_run_status do |workflow|
    workflow.runs.max_by(&:created_at)&.state
  end

  typelize :boolean
  attribute :has_active_runs do |workflow|
    workflow.runs.any? { |r| %w[running paused].include?(r.state) }
  end

  typelize :string?
  attribute :description_excerpt do |workflow|
    workflow.description&.truncate(100)
  end

  typelize :boolean
  attribute :inherit_all_project_resources do |workflow|
    workflow.inherit_all_project_resources
  end

  typelize "number[]"
  attribute :base_tool_ids do |workflow|
    workflow.base_tool_ids
  end

  typelize "number[]"
  attribute :base_skill_ids do |workflow|
    workflow.base_skill_ids
  end

  typelize "number[]"
  attribute :base_mcp_server_ids do |workflow|
    workflow.base_mcp_server_ids
  end

  typelize "number[]"
  attribute :base_asset_ids do |workflow|
    workflow.base_asset_ids
  end
end
