# frozen_string_literal: true

module InternalTools
  class BoardListMembers < Base
    tool do
      display_name "Board List Members"
      description "List the people who can access this board's project, with the user IDs to assign a task to, " \
                  "and the project's teams, with the team IDs a task can be assigned to instead."
      tags :board
      inject_when :workflow_step_session
      read_only
      input_schema({
        type: "object",
        required: [],
        properties: {}
      })
    end

    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      board_project = board.project
      return error("This board has no project") unless board_project

      members = board_project.assignable_users.map do |u|
        { id: u.id, name: u.name, role: u.id == board_project.owner_id ? "owner" : "collaborator" }
      end
      teams = board_project.project_teams.includes(:members).map do |team|
        { id: team.id, name: team.name, strategy: team.strategy.to_s, member_ids: team.members.map(&:id) }
      end
      success({ project_id: board_project.id, members: members, teams: teams }.to_json)
    end
  end
end
