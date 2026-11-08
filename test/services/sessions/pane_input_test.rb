# frozen_string_literal: true

require "test_helper"

module Sessions
  class PaneInputTest < ActiveSupport::TestCase
    setup do
      @runtime = stub_container_runtime
      user = create(:user, :with_company)
      project = create(:project, owner: user, company: user.companies.first)
      @session = create(:terminal_session, user: user, project: project, container_id: "ctr-pane")
      Rails.logger.stubs(:warn)
    end

    teardown do
      cleanup_runtime_overrides
    end

    # Two execs could fail between the text and its Enter, leaving an unsent draft in the
    # prompt box.
    test "types the text and submits it in one tmux call" do
      assert PaneInput.type(@session, "Continue; then finish.", runtime: @runtime)

      assert_equal [ [ "tmux", "send-keys", "-t", "agent", "-l", "Continue; then finish.", ";",
                       "send-keys", "-t", "agent", "Enter" ] ], @runtime.execs
    end

    test "answers false when tmux refuses the keys" do
      @runtime.fail_exec("send-keys")

      refute PaneInput.type(@session, "hello", runtime: @runtime)
    end

    test "answers false when the exec itself fails" do
      @runtime.raise_on_exec("send-keys")

      refute PaneInput.type(@session, "hello", runtime: @runtime)
    end

    test "types nothing into a session without a container" do
      @session.update_columns(container_id: nil)

      refute PaneInput.type(@session, "hello", runtime: @runtime)
      assert_empty @runtime.execs
    end
  end
end
