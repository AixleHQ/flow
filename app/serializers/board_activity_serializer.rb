# frozen_string_literal: true

class BoardActivitySerializer < ApplicationSerializer
  attributes :id, :event_type, :actor_id, :actor_type, :actor_name,
             :board_task_id, :task_title, :description, :metadata, :created_at

  def actor_name
    user = object.actor
    case object.actor_type
    when "agent"
      "Agent (managed by #{user.name})"
    else
      user.name
    end
  end

  def task_title
    object.board_task&.title
  end

  def description
    case object.event_type
    when "task_moved"
      "#{actor_name} moved '#{task_title}' from #{object.metadata['from_column']} to #{object.metadata['to_column']}"
    when "task_created"
      "#{actor_name} created '#{object.metadata['title'] || task_title}'"
    when "task_updated"
      "#{actor_name} updated '#{task_title}'"
    when "task_deleted"
      "#{actor_name} deleted '#{object.metadata['title']}'"
    when "comment_added"
      tag_info = object.metadata["tag"].present? ? " with tag '#{object.metadata['tag']}'" : ""
      "#{actor_name} added comment#{tag_info} on '#{task_title}'"
    when "asset_attached"
      "#{actor_name} attached '#{object.metadata['name']}' to '#{task_title}'"
    when "workflow_started"
      "Workflow '#{object.metadata['workflow_name']}' started on '#{task_title}'"
    when "workflow_completed"
      "Workflow '#{object.metadata['workflow_name']}' completed on '#{task_title}'"
    when "workflow_failed"
      "Workflow '#{object.metadata['workflow_name']}' failed on '#{task_title}'"
    when "human_help_requested"
      "Agent requested help on '#{task_title}': #{object.metadata['question'].to_s.truncate(80)}"
    else
      "#{actor_name} performed #{object.event_type.to_s.humanize.downcase}"
    end
  end
end
