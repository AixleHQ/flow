# frozen_string_literal: true

class ProjectResource < ApplicationResource
  attributes :id, :name, :description, :slug, :state, :created_at, :updated_at

  typelize :number
  attribute :collaborators_count do |project|
    if project.respond_to?(:cached_collaborators_count)
      project.cached_collaborators_count.to_i
    else
      project.project_collaborators.size
    end
  end

  typelize :number
  attribute :members_count do |project|
    if project.respond_to?(:cached_collaborators_count)
      project.cached_collaborators_count.to_i + 1
    else
      project.project_collaborators.size + 1
    end
  end

  typelize "string | null"
  attribute :last_activity_at do |project|
    if project.respond_to?(:cached_last_activity_at)
      project.cached_last_activity_at
    else
      project.terminal_sessions.maximum(:started_at)
    end
  end

  typelize :number
  attribute :sessions_count do |project|
    if project.respond_to?(:cached_sessions_count)
      project.cached_sessions_count.to_i
    else
      project.terminal_sessions.count
    end
  end

  typelize :number
  attribute :workflows_count do |project|
    if project.respond_to?(:cached_workflows_count)
      project.cached_workflows_count.to_i
    else
      project.workflows.where(deleted_at: nil).count
    end
  end

  typelize :number
  attribute :board_tasks_count do |project|
    if project.respond_to?(:cached_board_tasks_count)
      project.cached_board_tasks_count.to_i
    else
      project.board&.board_tasks&.count || 0
    end
  end

  # Capped preview for the avatar stack (owner first, then collaborators). The
  # full count is `members_count` above; the UI renders "+N" for the remainder.
  # Opt-in via `params[:with_members]` — the sidebar's project list (rendered on
  # EVERY page via ApplicationController's shared props) doesn't show avatars,
  # so loading owner+collaborators for it would be pure N+1 cost; only the
  # Projects index page, which does show them, passes the flag.
  # Reads from `owner`/`collaborators` associations directly (expected to be
  # preloaded by the controller) rather than `Project#member_users`, which
  # re-queries and would defeat that preload.
  typelize "Array<{ id: number; initials: string }>"
  attribute :members do |project|
    next [] unless params[:with_members]

    ([ project.owner ] + project.collaborators.to_a).first(4).map do |user|
      { id: user.id, initials: self.class.initials_for(user.name) }
    end
  end

  def self.initials_for(name)
    parts = name.to_s.strip.split(/\s+/)
    return "" if parts.empty?
    return parts.first[0, 2].upcase if parts.length == 1

    "#{parts.first[0]}#{parts.last[0]}".upcase
  end
end
