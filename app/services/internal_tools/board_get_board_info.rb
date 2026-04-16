# frozen_string_literal: true

module InternalTools
  class BoardGetBoardInfo < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      result = BoardResource.new(board, params: { include_columns: true }).to_h
      success(result.to_json)
    end
  end
end
