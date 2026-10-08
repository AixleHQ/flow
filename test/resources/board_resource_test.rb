# frozen_string_literal: true

require "test_helper"

class BoardResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board = create(:board, project: @project)
  end

  test "bound columns render in a fixed number of queries, however many there are" do
    workflow = create(:workflow, scope: @project, name: "Triage")
    3.times do |i|
      column = create(:board_column, board: @board, name: "Column #{i}")
      ColumnWorkflowBinding.create!(board_column: column, workflow: workflow, created_by: @user)
    end

    columns = nil
    assert_queries_count(3) do
      columns = BoardResource.new(@board, params: { include_columns: true, snake_keys: true }).to_h["board_columns"]
    end

    assert_equal [ "Triage" ] * 3, columns.map { |c| c.dig("workflow_binding", :workflow_name) }
  end
end
