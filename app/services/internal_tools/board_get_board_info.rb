# frozen_string_literal: true

module InternalTools
  class BoardGetBoardInfo < Base
    tool do
      display_name "Board Get Board Info"
      description "Return the current board with its columns and related metadata for the active workflow task."
      tags :board
      inject_when :workflow_step_session
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

      result = BoardResource.new(board, params: { include_columns: true }).to_h
      success(result.to_json)
    end
  end
end
