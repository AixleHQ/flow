# frozen_string_literal: true

class WorkflowSerializer < ApplicationSerializer
  include ScopeIndicatorSerialization

  attributes :id, :name, :description, :config, :scope_type, :scope_id,
             :steps_count, :last_run_at, :last_run_status,
             :has_active_runs, :description_excerpt,
             :created_at, :updated_at

  def config
    object.config
  end

  def steps_count
    object.steps.size
  end

  def last_run_at
    return nil unless object.respond_to?(:runs)

    object.runs.order(created_at: :desc).pick(:created_at)
  end

  def last_run_status
    return nil unless object.respond_to?(:runs)

    object.runs.order(created_at: :desc).pick(:state)
  end

  def has_active_runs
    return false unless object.respond_to?(:runs)

    object.runs.where(state: %w[running paused]).exists?
  end

  def description_excerpt
    return nil if object.description.blank?

    object.description.truncate(100)
  end
end
