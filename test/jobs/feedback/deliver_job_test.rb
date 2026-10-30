# frozen_string_literal: true

require "test_helper"

class Feedback::DeliverJobTest < ActiveJob::TestCase
  setup do
    company = create(:company)
    project = create(:project, company: company, owner: create(:user, company: company))
    @column = create(:board_column, board: create(:board, project: project))
    Settings.stubs(:feedback).returns(Hashie::Mash.new(board_project_id: project.id, board_column_id: @column.id))
  end

  test "delivers the submission to the destination it names" do
    submission = create(:feedback_submission)

    Feedback::DeliverJob.perform_now(submission, "board")

    assert_equal 1, @column.board_tasks.count
    assert submission.reload.board_delivered_at
  end

  test "drops a submission deleted before its turn" do
    submission = create(:feedback_submission)
    Feedback::DeliverJob.perform_later(submission, "board")
    submission.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_equal 0, @column.board_tasks.count
  end
end
