# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class TerminalSessionsControllerTest < ActionController::TestCase
      setup do
        @user = create(:user, :with_company)
        @company = @user.company
        sign_in(@user)
      end

      # Helper to parse JSON response
      def json
        JSON.parse(response.body)
      end

      # INDEX tests
      test "#index returns all terminal sessions for current user" do
        session1 = create(:terminal_session, :auth_setup, user: @user, agent_type: "claude_code")
        session2 = create(:terminal_session, :auth_setup, user: @user, agent_type: "cursor_cli")
        other_user = create(:user, :with_company)
        other_user_session = create(:terminal_session, :auth_setup, user: other_user, agent_type: "codex")

        get :index
        assert_response :success

        session_ids = json["items"].pluck("id")
        assert_includes session_ids, session1.id
        assert_includes session_ids, session2.id
        assert_not_includes session_ids, other_user_session.id
      end

      test "#index orders by created_at desc" do
        old_session = create(:terminal_session, :auth_setup, user: @user, created_at: 2.days.ago)
        new_session = create(:terminal_session, :auth_setup, user: @user, created_at: 1.hour.ago)

        get :index
        assert_response :success

        session_ids = json["items"].pluck("id")
        assert_equal [new_session.id, old_session.id], session_ids
      end

      # SHOW tests
      test "#show returns single terminal session" do
        session = create(:terminal_session, :running, user: @user, agent_type: "claude_code")

        get :show, params: { id: session.id }
        assert_response :success

        data = json["data"]
        assert_equal session.id, data["id"]
        assert_equal "claude_code", data["agentType"]
        assert_equal "running", data["state"]
        assert_not_nil data["websocketUrl"]
      end

      test "#show returns 404 for other user's session" do
        other_user = create(:user, :with_company)
        other_session = create(:terminal_session, :auth_setup, user: other_user)

        get :show, params: { id: other_session.id }
        assert_response :not_found
      end

      # CREATE tests
      test "#create creates auth_setup terminal session" do
        assert_difference -> { TerminalSession.count }, 1 do
          post :create, params: {
            terminal_session: attributes_for(:terminal_session,
              session_type: "auth_setup",
              agent_type: "claude_code",
              project_id: nil)
          }
        end

        assert_response :created
        data = json["data"]
        assert_equal "claude_code", data["agentType"]
        assert_equal "auth_setup", data["sessionType"]
        # After create, AASM start! is triggered
        assert_equal "started", data["state"]
      end

      test "#create validates agent_type presence for auth_setup" do
        assert_no_difference -> { TerminalSession.count } do
          post :create, params: {
            terminal_session: attributes_for(:terminal_session,
              session_type: "auth_setup",
              agent_type: nil)
          }
        end

        assert_response :unprocessable_entity
        assert_not_nil json["errors"]
      end

      test "#create validates agent_type inclusion" do
        assert_no_difference -> { TerminalSession.count } do
          post :create, params: {
            terminal_session: attributes_for(:terminal_session,
              session_type: "auth_setup",
              agent_type: "invalid_agent")
          }
        end

        assert_response :unprocessable_entity
      end

      # UPDATE tests
      test "#update can modify session metadata" do
        session = create(:terminal_session, user: @user, metadata: { theme: "light" })

        patch :update, params: {
          id: session.id,
          terminal_session: { metadata: { theme: "dark", lang: "en" } }
        }

        assert_response :success
        session.reload
        assert_equal "dark", session.metadata["theme"]
        assert_equal "en", session.metadata["lang"]
      end

      test "#update cannot modify other user's session" do
        other_user = create(:user, :with_company)
        other_session = create(:terminal_session, :auth_setup, user: other_user)

        patch :update, params: {
          id: other_session.id,
          terminal_session: { metadata: { test: "value" } }
        }

        assert_response :not_found
      end

      # FINISH_AUTH tests
      test "#finish_auth marks session as stopped and triggers artifact collection" do
        session = create(:terminal_session, user: @user, state: "running", session_type: "auth_setup")

        post :finish_auth, params: { id: session.id }
        assert_response :success

        session.reload
        assert_equal "stopped", session.state
        assert_not_nil json["message"]
      end

      test "#finish_auth returns error for non-auth_setup sessions" do
        project = create(:project, owner: @user, company: @company)
        session = create(:terminal_session, :agent_session, user: @user, project: project, state: "running")

        post :finish_auth, params: { id: session.id }
        assert_response :bad_request
        assert_includes json["error"], "auth_setup"
      end

      test "#finish_auth returns error if session cannot be stopped" do
        session = create(:terminal_session, user: @user, state: "not_started")

        post :finish_auth, params: { id: session.id }
        assert_response :bad_request
        assert_includes json["error"], "cannot be stopped"
      end

      # CANCEL tests
      test "#cancel cancels active session" do
        session = create(:terminal_session, user: @user, state: "running")

        post :cancel, params: { id: session.id }
        assert_response :success

        session.reload
        assert_equal "cancelled", session.state
      end

      test "#cancel returns error if session cannot be cancelled" do
        session = create(:terminal_session, :collected, user: @user)

        post :cancel, params: { id: session.id }
        assert_response :bad_request
      end

      # DESTROY tests
      test "#destroy deletes non-active session" do
        session = create(:terminal_session, :collected, user: @user)

        assert_difference -> { TerminalSession.count }, -1 do
          delete :destroy, params: { id: session.id }
        end

        assert_response :ok
      end

      test "#destroy returns error for active session" do
        session = create(:terminal_session, user: @user, state: "running")

        assert_no_difference -> { TerminalSession.count } do
          delete :destroy, params: { id: session.id }
        end

        assert_response :bad_request
        assert_includes json["error"], "Cannot delete active session"
      end

      test "#destroy cannot delete other user's session" do
        other_user = create(:user, :with_company)
        other_session = create(:terminal_session, :collected, user: other_user)

        assert_no_difference -> { TerminalSession.count } do
          delete :destroy, params: { id: other_session.id }
        end

        assert_response :not_found
      end
    end
  end
end
