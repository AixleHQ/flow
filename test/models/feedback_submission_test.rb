# frozen_string_literal: true

require "test_helper"

class FeedbackSubmissionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
  end

  def submission(**attributes)
    FeedbackSubmission.new({ company: @company, user: @user, kind: "bug", message: "Broken" }.merge(attributes))
  end

  test "a message of a known kind from a person is valid" do
    %w[bug feature_request support].each do |kind|
      record = submission(kind: kind)
      assert record.valid?, record.errors.full_messages.to_sentence
    end
  end

  test "needs a message within the limit, a known kind and a sender" do
    assert_includes submission(message: " ").tap(&:validate).errors[:message], "can't be blank"
    assert_not submission(message: "x" * (FeedbackSubmission::MESSAGE_MAX + 1)).valid?
    assert_not submission(kind: "praise").valid?
    assert_not submission(user: nil).valid?
    assert_not submission(page_url: "https://example.com/#{'a' * FeedbackSubmission::PAGE_URL_MAX}").valid?
  end

  test "a person may send a limited number of messages an hour" do
    freeze_time
    create_list(:feedback_submission, FeedbackSubmission::HOURLY_LIMIT, company: @company, user: @user)

    refused = submission
    assert_not refused.valid?
    assert_match(/try again later/, refused.errors[:base].sole)
    assert submission(user: create(:user, company: @company)).valid?, "the limit is per person"

    travel 61.minutes
    assert submission.valid?
  end

  def upload(name, content = "log line")
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/plain", original_filename: name)
  end

  test "keeps attached files under the names they were sent with" do
    record = submission.tap { |s| s.attach([ upload("console.log"), upload("trace.txt") ]) }

    assert record.save, record.errors.full_messages.to_sentence
    assert_equal %w[console.log trace.txt], record.attachments.map(&:name)
    assert_equal "log line", record.attachments.first.file.read
  end

  test "names each file it refuses, and takes only so many" do
    too_large = submission.tap { |s| s.attach([ upload("recording.mov", "x" * (FeedbackAttachment::MAX_SIZE + 1)) ]) }
    assert_not too_large.valid?
    assert_equal [ "recording.mov is too large (max is 20 MB)." ], too_large.errors[:base]

    too_many = submission.tap { |s| s.attach(Array.new(FeedbackSubmission::ATTACHMENTS_MAX + 1) { |i| upload("#{i}.txt") }) }
    assert_not too_many.valid?
    assert_equal [ "Attach at most #{FeedbackSubmission::ATTACHMENTS_MAX} files." ], too_many.errors[:base]
  end
end
