# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Internal
      # The Traefik ForwardAuth gate in front of the container routes (ttyd, the
      # IDE, the file server). It is the only thing standing between a route
      # token and a live shell, so the sharing preferences have to hold HERE —
      # letting the session page render a websocket URL that the proxy then
      # refuses would make "show my active sessions" a page that opens onto a
      # 403, and skipping the check would make the preference decorative.
      class WsAuthSharingTest < ActionDispatch::IntegrationTest
        setup do
          @company = create(:company)
          @owner = create(:user, :employee, :onboarding_completed, company: @company,
                                                                   share_active_sessions: true,
                                                                   password: AuthHelper::TEST_PASSWORD)
          @member = create(:user, :employee, :onboarding_completed, company: @company,
                                                                    password: AuthHelper::TEST_PASSWORD)
          @project = create(:project, company: @company, owner: @owner)
          @project.add_collaborator(@member)

          @session = create(:terminal_session, :agent_session, user: @owner, project: @project, state: "ready")
        end

        test "a project member reaches the terminal of a shared running session" do
          sign_in_as(@member)

          get_ws_auth(@session)

          assert_response :ok
        end

        test "the terminal closes to them the moment the owner stops sharing" do
          @owner.update!(share_active_sessions: false)
          sign_in_as(@member)

          get_ws_auth(@session)

          assert_response :forbidden
        end

        test "someone outside the project is refused even while the owner shares" do
          stranger = create(:user, :employee, :onboarding_completed, company: @company,
                                                                     password: AuthHelper::TEST_PASSWORD)
          sign_in_as(stranger)

          get_ws_auth(@session)

          # Sharing is not publication: the route token grants nothing on its own,
          # and reachability of the project is still required.
          assert_response :forbidden
        end

        test "the owner reaches their own terminal while sharing nothing" do
          @owner.update!(share_active_sessions: false, share_completed_sessions: false)
          sign_in_as(@owner)

          get_ws_auth(@session)

          assert_response :ok
        end

        private

        def get_ws_auth(session, suffix: "tty/ws")
          get api_v1_internal_ws_auth_path,
              headers: { "X-Forwarded-Uri" => "/t/#{session.route_token}/#{suffix}" }
        end
      end
    end
  end
end
