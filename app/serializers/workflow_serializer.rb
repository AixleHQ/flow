# frozen_string_literal: true

class WorkflowSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :description, :config, :scope_type, :scope_id,
             :steps_count, :last_run_at, :last_run_status,
             :has_active_runs, :description_excerpt,
             :base_tool_ids, :base_skill_ids, :base_mcp_server_ids,
             :base_asset_ids, :inherit_all_project_resources,
             :created_at, :updated_at

  def config
    object.config
  end

  def steps_count
    object.steps.not_deleted.size
  end

  def last_run_at
    return nil unless object.respond_to?(:runs)

    latest_run&.created_at
  end

  def last_run_status
    return nil unless object.respond_to?(:runs)

    latest_run&.state
  end

  def has_active_runs
    return false unless object.respond_to?(:runs)

    object.runs.any? { |r| %w[running paused].include?(r.state) }
  end

  def description_excerpt
    return nil if object.description.blank?

    object.description.truncate(100)
  end

  private

  def latest_run
    @latest_run ||= object.runs.sort_by(&:created_at).last
  end
end
