# frozen_string_literal: true

require "test_helper"

class ChatConnectCodeTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @project = create(:project, owner: @user, company: @user.companies.first)
  end

  test "a code is shown once and stored only as its digest, for ten minutes" do
    freeze_time do
      record, code = ChatConnectCode.issue!(project: @project, provider: "slack", user: @user)

      assert_match(/\Aaixle-[0-9A-HJKMNP-TV-Z]{8}\z/, code)
      assert_equal ChatConnectCode.digest(code), record.code_digest
      assert_not_includes record.attributes.values.map(&:to_s), code
      assert_equal [ @project.company_id, 10.minutes.from_now ], [ record.company_id, record.expires_at ]
      assert_equal "pending", record.state
      travel 10.minutes
      assert_equal "expired", record.state
    end
  end

  test "the code is found in a message however it was typed, and nothing else passes for one" do
    assert_equal "aixle-7F3K9QXM", ChatConnectCode.extract("connect Aixle-7f3k9qxm please")
    assert_equal ChatConnectCode.digest("aixle-7F3K9QXM"), ChatConnectCode.digest("AIXLE-7f3k9qxm")
    assert_nil ChatConnectCode.extract("connect aixle-7F3K9QX")
    assert_nil ChatConnectCode.extract("connect aixle-ILOU0000"), "I, L, O and U are not in the alphabet"
  end

  test "a company holds at most ten unused codes at a time" do
    ChatConnectCode::MAX_OPEN_PER_COMPANY.times { ChatConnectCode.issue!(project: @project, provider: "slack", user: @user) }

    error = assert_raises(ActiveRecord::RecordInvalid) { ChatConnectCode.issue!(project: @project, provider: "slack", user: @user) }
    assert_match(/Too many unused codes/, error.message)

    travel(11.minutes) { assert ChatConnectCode.issue!(project: @project, provider: "teams", user: @user).first.persisted? }
  end
end
