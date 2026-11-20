# frozen_string_literal: true

require "test_helper"

module Sessions
  class SuspensionExpiryTest < ActiveSupport::TestCase
    include CheckpointStorageHelper
    include ActionMailer::TestHelper

    setup do
      @user = create(:user, :with_company)
      @project = create(:project, owner: @user, company: @user.companies.first)
      use_checkpoint_storage
    end

    teardown { restore_checkpoint_storage }

    def suspended_session(expires_at:)
      create(:terminal_session, :agent_session, user: @user, project: @project, mode: "interactive",
                                                state: "suspended", suspended_at: expires_at - 30.days,
                                                restore_expires_at: expires_at)
    end

    # A finished session's outputs become assets; a forgotten suspended one must not lose them.
    test "a closed restore window turns the saved outputs into assets and finishes the session" do
      session = suspended_session(expires_at: 1.hour.ago)
      create_checkpoint(session, archive: checkpoint_archive(workspace_files: {
        "outputs/report.md" => "# Report", "outputs/charts/q3.csv" => "a,b", "notes/draft.md" => "not an output"
      }))

      assert_equal 1, SuspensionExpiry.expire_due

      session.reload
      assert_equal "finished", session.state
      assert session.metadata[Suspension::EXPIRED_KEY]
      assert_nil session.session_checkpoint
      assets = session.output_assets.order(:name)
      assert_equal [ "charts/q3.csv", "report.md" ], assets.map(&:name)
      assert(assets.all? { |asset| asset.status == "pending_review" })
      assert_equal "# Report", assets.last.latest_version.file.read
    end

    test "a session still inside its window is left alone" do
      session = suspended_session(expires_at: 2.days.from_now)
      create_checkpoint(session)

      assert_equal 0, SuspensionExpiry.expire_due

      assert session.reload.suspended?
      assert session.session_checkpoint
    end

    # Kept until the date, so a restore that failed can be tried again.
    test "a restored session's archive is deleted when its window closes" do
      session = suspended_session(expires_at: 1.hour.ago)
      create_checkpoint(session)
      session.update!(state: "restored")

      SuspensionExpiry.expire_due

      assert_equal "restored", session.reload.state
      assert_nil session.session_checkpoint
    end

    test "the owner is reminded once, three days before the window closes" do
      due = suspended_session(expires_at: 2.days.from_now)
      suspended_session(expires_at: 10.days.from_now)

      assert_enqueued_emails 1 do
        assert_equal 1, SuspensionExpiry.remind_due
      end
      assert due.reload.metadata[Suspension::REMINDED_KEY]

      assert_no_enqueued_emails { SuspensionExpiry.remind_due }
    end
  end
end
