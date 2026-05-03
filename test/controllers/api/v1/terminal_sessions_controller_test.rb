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
        assert_equal true, captured[:session_config]["bmad_enabled"]
        assert_equal %w[bmm cis], captured[:session_config]["bmad_modules"]
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
    end
  end
end
