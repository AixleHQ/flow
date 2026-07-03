# frozen_string_literal: true

module PersonalTools
  class UpdateBoardColumn < Base
    tool do
      display_name "Update Board Column"
      description "Update a board column's name or purpose. Requires project-admin (owner)."
      audience :user
      tags :board
      param :project_id, type: :integer, description: "Project id.", required: true
      param :column_id, type: :integer, description: "Column id.", required: true
      param :name, type: :string, description: "New name."
      param :purpose, type: :string, description: "New purpose."
    end

    ATTRS = %w[name purpose].freeze

    def execute
      project = find_project!
      authorize!(project.board, :update?, policy: Web::Company::Projects::Board::ColumnsPolicy, project: project)
      column = project.board&.board_columns&.find_by(id: params[:column_id])
      return error("Column not found on this board") unless column

      attrs = params.slice(*ATTRS).reject { |_, v| v.nil? }
      return error("No fields to update") if attrs.empty?

      column.update!(attrs)
      success(id: column.id, name: column.name, updated_fields: attrs.keys)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update column: #{e.message}")
    end
  end
end
