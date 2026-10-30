# frozen_string_literal: true

require "test_helper"

class FeedbackTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def configure(slack_bot_token: "", slack_channel_id: "", board_project_id: nil, board_column_id: nil)
    Settings.stubs(:feedback).returns(Hashie::Mash.new(
      slack_bot_token: slack_bot_token, slack_channel_id: slack_channel_id,
      board_project_id: board_project_id, board_column_id: board_column_id
    ))
  end

  test "is off until a destination is configured" do
    configure
    assert_not Feedback.enabled?

    configure(board_project_id: 1)
    assert_not Feedback.enabled?, "a board needs its column too"

    configure(board_project_id: 1, board_column_id: 2)
    assert Feedback.enabled?

    configure(slack_bot_token: "xoxb-1")
    assert_not Feedback.enabled?, "a bot needs its channel too"

    configure(slack_bot_token: "xoxb-1", slack_channel_id: "C1")
    assert Feedback.enabled?
  end

  test "delivers to each configured destination in a job of its own" do
    configure(slack_bot_token: "xoxb-1", slack_channel_id: "C1", board_project_id: 1, board_column_id: 2)
    submission = create(:feedback_submission)

    assert_enqueued_jobs 2, only: Feedback::DeliverJob do
      Feedback.deliver_later(submission)
    end
    assert_enqueued_with(job: Feedback::DeliverJob, args: [ submission, "slack" ])
    assert_enqueued_with(job: Feedback::DeliverJob, args: [ submission, "board" ])
  end

  test "delivers only where it is configured" do
    configure(board_project_id: 1, board_column_id: 2)
    submission = create(:feedback_submission)

    Feedback.deliver_later(submission)

    assert_enqueued_jobs 1, only: Feedback::DeliverJob
    assert_enqueued_with(job: Feedback::DeliverJob, args: [ submission, "board" ])
  end
end
