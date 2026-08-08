# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # The log replay endpoint is the one read on this controller that is NOT
    # owner-only: "show my finished sessions" would mean nothing if the page
    # opened and the log behind it 404'd. It widens to sessions in projects the
    # caller can reach, and only while the owner shares them — every mutating
    # action here stays scoped to `current_user.terminal_sessions`.
    class TerminalSessionsLogVisibilityTest < ActionDispatch::IntegrationTest
      setup do
        @company = create(:company)
        @owner = create(:user, :employee, :onboarding_completed, company: @company,
                                                                 share_completed_sessions: true,
                                                                 password: AuthHelper::TEST_PASSWORD)
        @member = create(:user, :employee, :onboarding_completed, company: @company,
                                                                  password: AuthHelper::TEST_PASSWORD)
        @project = create(:project, company: @company, owner: @owner)
        @project.add_collaborator(@member)

        @session = create(:terminal_session, :agent_session, user: @owner, project: @project, state: "finished")
        attach_terminal_log(@session, "\e[31mred\e[0m output")

        sign_in_as(@member)
      end

      test "a project member replays a shared finished session" do
        get terminal_log_api_v1_terminal_session_path(@session)

        assert_response :success
        assert_includes response.body, "red"
      end

      test "the log disappears with the owner's preference" do
        @owner.update!(share_completed_sessions: false)

        get terminal_log_api_v1_terminal_session_path(@session)

        # 404, not 403: a session its owner keeps private should not be
        # distinguishable from one that does not exist.
        assert_response :not_found
      end

      test "someone outside the project gets nothing even when the owner shares" do
        stranger = create(:user, :employee, :onboarding_completed, company: @company,
                                                                   password: AuthHelper::TEST_PASSWORD)
        sign_in_as(stranger)

        get terminal_log_api_v1_terminal_session_path(@session)

        assert_response :not_found
      end

      test "the owner replays their own log while sharing nothing" do
        @owner.update!(share_active_sessions: false, share_completed_sessions: false)
        sign_in_as(@owner)

        get terminal_log_api_v1_terminal_session_path(@session)

        assert_response :success
        assert_includes response.body, "red"
      end

      private

      def attach_terminal_log(session, body)
        io = StringIO.new(body)
        io.define_singleton_method(:original_filename) { "terminal_output.log" }
        SessionLog.create!(terminal_session: session, name: "terminal_output.log", file: io,
                           file_size: body.bytesize, content_type: "text/plain; charset=utf-8")
      end
    end
  end
end
