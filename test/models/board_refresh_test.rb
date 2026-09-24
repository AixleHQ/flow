# frozen_string_literal: true

require "test_helper"

class BoardRefreshTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    @board = create(:board, project: create(:project, company: user.companies.first, owner: user))
  end

  test "inside a unit of work each board refreshes once, when the work is done" do
    touched = []
    @board.update_column(:updated_at, 1.hour.ago)
    before = @board.reload.updated_at

    Rails.application.executor.wrap do
      3.times { BoardRefresh.request(Board.find(@board.id)) }
      touched << @board.reload.updated_at
    end

    assert_equal before, touched.first, "no refresh while the work is still running"
    assert_operator @board.reload.updated_at, :>, before
  end

  test "outside a unit of work the board refreshes at once" do
    @board.update_column(:updated_at, 1.hour.ago)
    before = @board.reload.updated_at

    BoardRefresh.request(@board)

    assert_operator @board.reload.updated_at, :>, before
  end
end
