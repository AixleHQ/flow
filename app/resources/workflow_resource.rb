# frozen_string_literal: true

class WorkflowResource < ApplicationResource
  attributes :id, :name, :description, :config, :scope_type, :scope_id, :created_at, :updated_at

  attribute :scope_indicator do |workflow|
    workflow.scope_indicator
  end

  attribute :steps_count do |workflow|
    workflow.steps.select { |s| s.deleted_at.nil? }.size
  end

  attribute :last_run_at do |workflow|
    workflow.runs.max_by(&:created_at)&.created_at
  end

  attribute :last_run_status do |workflow|
    workflow.runs.max_by(&:created_at)&.state
  end

  attribute :has_active_runs do |workflow|
    workflow.runs.any? { |r| %w[running paused].include?(r.state) }
  end

  attribute :description_excerpt do |workflow|
    workflow.description&.truncate(100)
  end

  attribute :inherit_all_project_resources do |workflow|
    workflow.inherit_all_project_resources
  end

  attribute :base_tool_ids do |workflow|
    workflow.base_tool_ids
  end

  attribute :base_skill_ids do |workflow|
    workflow.base_skill_ids
  end

  attribute :base_mcp_server_ids do |workflow|
    workflow.base_mcp_server_ids
  end

  attribute :base_asset_ids do |workflow|
    workflow.base_asset_ids
  end
end
