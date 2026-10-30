# frozen_string_literal: true

require "test_helper"

class Web::Company::FeedbackTest < ActionDispatch::IntegrationTest
  setup do
    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: "xoxb-1", slack_channel_id: "C1"))
    @company = create(:company)
  end

  def member(role)
    create(:user, role, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  def send_feedback(**feedback)
    post company_feedback_path,
         params: { feedback: { kind: "bug", message: "Board is blank", page_url: "https://flow.example.com/x" }.merge(feedback) },
         headers: { "Referer" => company_projects_url }
  end

  test "a member's feedback is kept with their company and themselves, and sent on" do
    user = member(:employee)
    sign_in_as(user)

    assert_enqueued_with(job: Feedback::DeliverJob) do
      send_feedback(user_id: create(:user).id, company_id: create(:company).id)
    end

    assert_redirected_to company_projects_url
    assert_match(/feedback has been sent/, flash[:notice])
    submission = FeedbackSubmission.sole
    assert_equal [ @company, user ], [ submission.company, submission.user ]
    assert_equal [ "bug", "Board is blank", "https://flow.example.com/x", Settings.app.version ],
                 [ submission.kind, submission.message, submission.page_url, submission.app_version ]
  end

  # Indexed, as the dialog sends them: Inertia's FormData names each file
  # feedback[attachments][0], [1], …
  test "files sent with the message are kept with it" do
    sign_in_as(member(:employee))

    send_feedback(attachments: { "0" => fixture_file_upload("logo.png", "image/png"),
                                 "1" => fixture_file_upload("test_file.txt", "text/plain") })

    assert_redirected_to company_projects_url
    attachments = FeedbackSubmission.sole.attachments.order(:id)
    assert_equal %w[logo.png test_file.txt], attachments.map(&:name)
    assert_equal "image/png", attachments.first.file.mime_type
  end

  test "files sent as a plain list are kept too" do
    sign_in_as(member(:employee))

    send_feedback(attachments: [ fixture_file_upload("test_file.txt", "text/plain") ])

    assert_equal %w[test_file.txt], FeedbackSubmission.sole.attachments.map(&:name)
  end

  test "a viewer sends feedback too" do
    sign_in_as(member(:viewer))

    send_feedback

    assert_equal 1, FeedbackSubmission.count
  end

  test "a refused message comes back with the reason and is not sent" do
    sign_in_as(member(:employee))

    assert_no_enqueued_jobs(only: Feedback::DeliverJob) { send_feedback(message: "") }

    assert_redirected_to company_projects_url
    assert_equal({ message: "Message can't be blank" }, session[:inertia_errors])
    assert_equal 0, FeedbackSubmission.count
  end

  test "there is nowhere to send it while no destination is configured" do
    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: "", slack_channel_id: ""))
    sign_in_as(member(:employee))

    send_feedback

    assert_response :not_found
    assert_equal 0, FeedbackSubmission.count
  end

  test "pages say whether feedback can be sent" do
    sign_in_as(member(:employee))

    get company_projects_path, headers: { "X-Inertia" => "true" }
    assert_equal true, response.parsed_body.dig("props", "settings", "feedbackEnabled") # rubocop:disable Minitest/AssertTruthy

    Settings.stubs(:feedback).returns(Hashie::Mash.new(slack_bot_token: "", slack_channel_id: ""))
    get company_projects_path, headers: { "X-Inertia" => "true" }
    assert_equal false, response.parsed_body.dig("props", "settings", "feedbackEnabled") # rubocop:disable Minitest/RefuteFalse
  end
end
