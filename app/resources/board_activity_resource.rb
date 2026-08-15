# frozen_string_literal: true

class BoardActivityResource < ApplicationResource
  attributes :id, :event_type, :actor_id, :actor_type,
             :board_task_id, :metadata, :created_at

  typelize metadata: "Record<string, unknown>"

  typelize :string
  attribute :actor_name do |activity|
    user = activity.actor
    case activity.actor_type
    when "agent"
      "Agent (managed by #{user.name})"
    else
      user.name
    end
  end

  typelize :string?
  attribute :task_title do |activity|
    activity.board_task&.title
  end

  typelize :string
  attribute :description do |activity|
    actor = case activity.actor_type
    when "agent" then "Agent (managed by #{activity.actor.name})"
    else activity.actor.name
    end
    task = activity.board_task&.title
    meta = activity.metadata || {}

    case activity.event_type
    when "task_moved"
      "#{actor} moved '#{task}' from #{meta['from_column']} to #{meta['to_column']}"
    when "task_created"
      "#{actor} created '#{meta['title'] || task}'"
    when "task_updated"
      "#{actor} updated '#{task}'"
    when "task_deleted"
      "#{actor} deleted '#{meta['title']}'"
    when "comment_added"
      tag_info = meta["tag"].present? ? " with tag '#{meta['tag']}'" : ""
      "#{actor} added comment#{tag_info} on '#{task}'"
    when "asset_attached"
      "#{actor} attached '#{meta['name']}' to '#{task}'"
    when "workflow_started"
      "Workflow '#{meta['workflow_name']}' started on '#{task}'"
    when "workflow_completed"
      "Workflow '#{meta['workflow_name']}' completed on '#{task}'"
    when "workflow_failed"
      "Workflow '#{meta['workflow_name']}' failed on '#{task}'"
    when "human_help_requested"
      "Agent requested help on '#{task}': #{meta['question'].to_s.truncate(80)}"
    when "gate_reconciled"
      "CI gate #{meta['gate_type']} on '#{task}' resolved as #{meta['conclusion'] || 'unknown'} by reconciliation"
    when "gate_stale"
      "CI gate #{meta['gate_type']} on '#{task}' marked stale: #{meta['reason'].to_s.truncate(120)}"
    else
      "#{actor} performed #{activity.event_type.to_s.humanize.downcase}"
    end
  end
end
