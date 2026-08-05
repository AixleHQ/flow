# frozen_string_literal: true

module InternalTools
  class BoardListMembers < Base
    tool do
      display_name "Board List Members"
      description "List the people who can access this board's project, with the user IDs to assign a task to."
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

      # Filtered by the same predicate BoardTask validates an assignee against,
      # so every id returned here is actually assignable (a collaborator whose
      # company membership was revoked still has a project_collaborators row).
      members = board_project.member_users.select { |u| board_project.accessible_by?(u) }.map do |u|
        { id: u.id, name: u.name, role: u.id == board_project.owner_id ? "owner" : "collaborator" }
      end
      success({ project_id: board_project.id, members: members }.to_json)
    end
  end
end
