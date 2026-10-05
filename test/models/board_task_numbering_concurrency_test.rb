# frozen_string_literal: true

require "test_helper"

# Racing creates need their own committed connections, so this test opts out of
# the transactional wrapper and cleans up after itself.
class BoardTaskNumberingConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  THREADS = 4

  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
  end

  teardown do
    BoardActivity.where(board_id: @board.id).delete_all
    BoardTask.where(board_id: @board.id).delete_all
    BoardColumn.where(board_id: @board.id).delete_all
    @board.delete
    # Before the user: projects.owner_id references it. Rows are deleted directly,
    # so `dependent: :destroy` never fires and every dependent is cleared by hand.
    @project.delete
    @user.company_memberships.delete_all
    UserIdentity.where(user_id: @user.id).delete_all
    UserSession.where(user_id: @user.id).delete_all
    @user.delete
    CompanyAuthPolicy.where(company_id: @company.id).delete_all
    IdentityProvider.where(company_id: @company.id).delete_all
    @company.delete
  end

  test "concurrent creates on one board get distinct, gapless numbers" do
    numbers = race(Array.new(THREADS) { |i| -> { create_through_service("Task #{i}") } })

    assert_equal (1..THREADS).to_a, numbers.sort
    assert_equal THREADS, @board.reload.last_task_number
  end

  private

  # Every job waits on one gate so they hit the board row together.
  def race(jobs)
    gate = Queue.new
    threads = jobs.map do |job|
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection { job.call }
      end
    end
    jobs.size.times { gate << true }
    threads.map(&:value)
  end

  # A board record of its own per thread, as each request has: records are not thread-safe.
  def create_through_service(title)
    board = Board.find(@board.id)
    TaskService.create(board: board, params: { title: title, board_column_id: @column.id }, actor: @user).number
  end
end
