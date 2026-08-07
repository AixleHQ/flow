# frozen_string_literal: true

module PersonalTools
  # The one board tool that has to exist before any other board tool works: a
  # project created over MCP has no board at all (boards are built from a
  # preset, historically only in the UI picker), so without this every
  # `create_board_column` / `create_board_task` call dead-ends on "This project
  # has no board".
  class SetupBoard < Base
    tool do
      display_name "Setup Board"
      description "Create a project's board from a preset — required before any other board tool works, " \
                  "since a project starts without one. Presets: simple_kanban (Backlog / In Progress / Done), " \
                  "dev_team (7 columns: backlog through tech design, implementation, code review, QA, release), " \
                  "full_sdlc (19 columns: design, tech design, dev, QA, UAT, release). Requires project-admin " \
                  "(owner). Rejected if the project already has a board — edit that one with the column tools."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id (from list_projects).", required: true
      param :preset, type: :string, description: "Which column set to create.",
                     enum: %w[simple_kanban dev_team full_sdlc], required: true
      param :name, type: :string, description: "Board name; defaults to the preset's display name."
    end

    def execute
      project = find_project!
      authorize!(project.board, :create?, policy: Web::Company::Projects::BoardsPolicy, project: project)
      if project.board
        return error("This project already has a board — use create_board_column / update_board_column " \
                     "/ delete_board_column to change its columns.")
      end
      unless BoardPresets.valid?(params[:preset])
        return error("Unknown preset: #{params[:preset]}. Use simple_kanban, dev_team or full_sdlc.")
      end

      board = Board.create_from_preset(project: project, preset_key: params[:preset], name: params[:name])
      success(board_id: board.id, name: board.name, preset: params[:preset], columns: columns_for(board))
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to set up board: #{e.message}")
    end

    private

    def columns_for(board)
      board.board_columns.order(:position).map do |c|
        { id: c.id, name: c.name, position: c.position, purpose: c.purpose }
      end
    end
  end
end
