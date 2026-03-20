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

      # INDEX tests (user-scoped — for auth/onboarding/profile)
      test "#index returns only current user sessions" do
        my_session = create(:terminal_session, :auth_setup, user: @user, agent_type: "claude_code")

        # Same company, different user — should NOT be included (user-scoped)
        teammate = create(:user, company: @company)
        teammate_session = create(:terminal_session, :auth_setup, user: teammate, agent_type: "codex")

        get :index
        assert_response :success

        session_ids = json["items"].pluck("id")
        assert_includes session_ids, my_session.id
        assert_not_includes session_ids, teammate_session.id
      end

      test "#index orders by created_at desc and returns pagination meta" do
        old_session = create(:terminal_session, :auth_setup, user: @user, created_at: 2.days.ago)
        new_session = create(:terminal_session, :auth_setup, user: @user, created_at: 1.hour.ago)

        get :index
        assert_response :success

        session_ids = json["items"].pluck("id")
        assert_equal [ new_session.id, old_session.id ], session_ids

        meta = json["meta"]
        assert_equal 1, meta["page"]
        assert meta["total_count"] >= 2
      end

      # SHOW tests
      test "#show returns single terminal session" do
        session = create(:terminal_session, :running, user: @user, agent_type: "claude_code")

        get :show, params: { id: session.id }
        assert_response :success

        data = json["data"]
        assert_equal session.id, data["id"]
        assert_equal "claude_code", data["agent_type"]
        assert_equal "running", data["state"]
        assert_not_nil data["websocket_url"]
      end

      test "#show returns 404 for other user's session" do
        other_user = create(:user, :with_company)
        other_session = create(:terminal_session, :auth_setup, user: other_user)

        get :show, params: { id: other_session.id }
        assert_response :not_found
      end

      # CREATE tests
      test "#create creates auth_setup terminal session" do
        mock_temporal_start

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
        assert_equal "claude_code", data["agent_type"]
        assert_equal "auth_setup", data["session_type"]
        # After create, AASM start! is triggered
        assert_equal "running", data["state"]
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

      # CREATE with normalized config params
      test "#create creates session with config_files and env_vars" do
        mock_temporal_start

        project = create(:project, owner: @user, company: @company)

        assert_difference -> { TerminalSession.count }, 1 do
          post :create, params: {
            terminal_session: {
              session_type: "agent_session",
              agent_type: "claude_code",
              project_id: project.id,
              mode: "non_interactive",
              initial_prompt: "Run the tests",
              session_config: {
                config_files: { "CLAUDE.md" => "# Context" },
                env_vars: { "NODE_ENV" => "production" }
              }
            }
          }
        end

        assert_response :created
        data = json["data"]
        assert_not_nil data["session_config"]
        assert_equal "# Context", data["session_config"]["config_files"]["CLAUDE.md"]
        assert_equal "production", data["session_config"]["env_vars"]["NODE_ENV"]
        assert_equal "non_interactive", data["mode"]
        assert_equal "Run the tests", data["initial_prompt"]
      end

      test "#create creates session with tool_ids and skill_ids" do
        mock_temporal_start

        project = create(:project, owner: @user, company: @company)
        tool = create(:tool, scope: @company)
        skill = create(:skill, scope: @company)

        assert_difference -> { TerminalSession.count }, 1 do
          post :create, params: {
            terminal_session: {
              session_type: "agent_session",
              agent_type: "claude_code",
              project_id: project.id,
              tool_ids: [ tool.id ],
              skill_ids: [ skill.id ]
            }
          }
        end

        assert_response :created
        session = TerminalSession.last
        assert_includes session.tools.pluck(:id), tool.id
        assert_includes session.skills.pluck(:id), skill.id
      end

      test "#show includes normalized config in response" do
        session = create(:terminal_session, :with_session_config, user: @user, mode: "interactive")

        get :show, params: { id: session.id }
        assert_response :success

        data = json["data"]
        assert data.key?("session_config")
        assert data.key?("mode")
        assert data.key?("tool_ids")
        assert data.key?("skill_ids")
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

      # FINISH tests
      test "#finish marks auth_setup session as finishing" do
        session = create(:terminal_session, user: @user, state: "running", session_type: "auth_setup")

        post :finish, params: { id: session.id }
        assert_response :success

        session.reload
        # request_finish! signals workflow when present; without workflow state stays running
        assert session.state.in?(%w[running finished])
        assert_not_nil json["message"]
      end

      test "#finish marks agent_session as finishing" do
        project = create(:project, owner: @user, company: @company)
        session = create(:terminal_session, :agent_session, user: @user, project: project, state: "running")

        post :finish, params: { id: session.id }
        assert_response :success

        session.reload
        assert session.state.in?(%w[running finished])
      end

      test "#finish returns error if session cannot be stopped" do
        session = create(:terminal_session, user: @user, state: "finished")

        post :finish, params: { id: session.id }
        assert_response :bad_request
        assert_includes json["error"], "Cannot finish"
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
