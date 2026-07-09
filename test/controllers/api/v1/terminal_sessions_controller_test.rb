# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class TerminalSessionsControllerTest < ActionController::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :onboarding_completed, company: @company)
        @project = create(:project, company: @company, owner: @user)
        sign_in @user
      end

      test "show returns session json" do
        ts = create(:terminal_session, user: @user, project: @project, state: "ready")

        get :show, params: { id: ts.id }

        assert_response :success
      end

      test "create returns created session" do
        mock_temporal_start
        SessionService.stubs(:create_and_start).returns(
          create(:terminal_session, :running, user: @user, project: @project)
        )

        post :create, params: {
          terminal_session: {
            session_type: "agent_session",
            agent_type: "claude_code",
            project_id: @project.id
          }
        }

        assert_response :created
      end

      test "create persists session_config with bmad flags" do
        mock_temporal_start
        captured = nil
        SessionService.stubs(:create_and_start).with do |**kwargs|
          captured = kwargs[:params]
          true
        end.returns(create(:terminal_session, :running, user: @user, project: @project))

        post :create, body: {
          terminal_session: {
            session_type: "agent_session",
            agent_type: "claude_code",
            project_id: @project.id,
            session_config: { bmad_enabled: true, bmad_modules: %w[bmm cis] }
          }
        }.to_json, as: :json

        assert_response :created
        assert captured[:session_config]["bmad_enabled"]
        assert_equal %w[bmm cis], captured[:session_config]["bmad_modules"]
      end

      test "create returns 422 with connect links when the OAuth preflight blocks launch" do
        SessionService.stubs(:create_and_start).raises(
          Oauth::PreflightError.new([ { mcp_server_id: 5, name: "Sentry", connect_url: "/oauth/mcp/5/connect" } ])
        )

        post :create, params: {
          terminal_session: { session_type: "agent_session", agent_type: "claude_code", project_id: @project.id }
        }

        assert_response :unprocessable_entity
        body = JSON.parse(response.body)
        assert_equal 1, body["reauth_required"].size
        assert_equal "/oauth/mcp/5/connect", body["reauth_required"].first["connect_url"]
      end

      test "destroy removes finished session" do
        ts = create(:terminal_session, user: @user, project: @project, state: "finished")

        delete :destroy, params: { id: ts.id }

        assert_response :success
      end

      test "finish returns session json" do
        ts = create(:terminal_session, :running, user: @user, project: @project)
        SessionService.stubs(:finish)

        post :finish, params: { id: ts.id }

        assert_response :success
      end

      # === viewer (read-only) enforcement ===

      class ViewerTest < ActionController::TestCase
        tests Api::V1::TerminalSessionsController

        setup do
          @company = create(:company)
          @owner = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @owner)
          @viewer = create(:user, :viewer, company: @company, email: "client@ext.com")
          @project.add_collaborator(@viewer)
          sign_in @viewer
        end

        test "viewer cannot launch an agent session" do
          post :create, params: {
            terminal_session: { session_type: "agent_session", agent_type: "claude_code", project_id: @project.id }
          }
          assert_response :forbidden
        end

        test "viewer cannot finish a session" do
          ts = create(:terminal_session, :running, user: @viewer, project: @project)
          post :finish, params: { id: ts.id }
          assert_response :forbidden
        end

        test "viewer can read own session" do
          ts = create(:terminal_session, user: @viewer, project: @project, state: "ready")
          get :show, params: { id: ts.id }
          assert_response :success
        end
      end
    end
  end
end
