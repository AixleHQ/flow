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

        test "a project member watches a shared running session through the read-only terminal" do
          sign_in_as(@member)

          get_ws_auth(@session, suffix: "view/ws")
          assert_response :ok

          get_ws_auth(@session, suffix: "fs/tree")
          assert_response :ok
        end

        # The container holds the owner's agent login, git token and vending keys:
        # a writable terminal or the IDE would hand all of that to whoever watches.
        test "nobody but the owner reaches the writable terminal or the IDE" do
          sign_in_as(@member)

          get_ws_auth(@session, suffix: "tty/ws")
          assert_response :forbidden

          get_ws_auth(@session, suffix: "ide/")
          assert_response :forbidden
        end

        test "a workflow step's container is read-only to everyone but the person who ran it" do
          step_session = create(:terminal_session, :running, user: @owner, project: @project,
                                                             session_type: "workflow_step", state: "ready")
          sign_in_as(@member)

          get_ws_auth(step_session, suffix: "view/ws")
          assert_response :ok

          get_ws_auth(step_session, suffix: "tty/ws")
          assert_response :forbidden
        end

        test "the read-only terminal closes to them the moment the owner stops sharing" do
          @owner.update!(share_active_sessions: false)
          sign_in_as(@member)

          get_ws_auth(@session, suffix: "view/ws")

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

        test "the owner reaches their own terminal and IDE while sharing nothing" do
          @owner.update!(share_active_sessions: false, share_completed_sessions: false)
          sign_in_as(@owner)

          get_ws_auth(@session)
          assert_response :ok

          get_ws_auth(@session, suffix: "ide/")
          assert_response :ok
        end

        # == served from a host of their own ==
        #
        # There the browser sends none of the app's cookies; the container URL
        # carries a pass, which the gate trades for a cookie on the sandbox host.

        test "a ticket in the URL admits its user, and is traded for a sandbox cookie" do
          ticket = ContainerTicket.issue(user: @member, session: @session)

          get_ws_auth(@session, suffix: "view/ws?#{ContainerTicket::PARAM}=#{CGI.escape(ticket)}")

          assert_response :ok
          assert_equal @member.id.to_s, response.headers["X-User-Id"]
          set_cookie = response.headers["Set-Cookie"].to_s
          assert_match(/\A#{ContainerTicket::COOKIE}=/, set_cookie)
          assert_includes set_cookie, "Path=/t/#{@session.route_token}/"
          assert_includes set_cookie, "HttpOnly"
        end

        test "the sandbox cookie admits its user on later requests" do
          value = ContainerTicket.issue(user: @member, session: @session, ttl: ContainerTicket::COOKIE_TTL)

          get api_v1_internal_ws_auth_path,
              headers: { "X-Forwarded-Uri" => "/t/#{@session.route_token}/view/ws",
                         "Cookie" => "#{ContainerTicket::COOKIE}=#{value}" }

          assert_response :ok
          assert_nil response.headers["Set-Cookie"]
        end

        test "a frame reloaded after its pass expired is admitted by the sandbox cookie" do
          ticket = ContainerTicket.issue(user: @member, session: @session)
          cookie = ContainerTicket.issue(user: @member, session: @session, ttl: ContainerTicket::COOKIE_TTL)

          travel ContainerTicket::TICKET_TTL + 1.minute do
            uri = "/t/#{@session.route_token}/view?#{ContainerTicket::PARAM}=#{CGI.escape(ticket)}"
            get api_v1_internal_ws_auth_path, headers: { "X-Forwarded-Uri" => uri }
            assert_response :unauthorized

            get api_v1_internal_ws_auth_path,
                headers: { "X-Forwarded-Uri" => uri, "Cookie" => "#{ContainerTicket::COOKIE}=#{cookie}" }
            assert_response :ok
            assert_equal @member.id.to_s, response.headers["X-User-Id"]
            assert_nil response.headers["Set-Cookie"]
          end
        end

        test "a ticket for another session, or a forged one, admits nobody" do
          other = create(:terminal_session, :agent_session, user: @owner, project: @project, state: "ready")
          ticket = ContainerTicket.issue(user: @member, session: other)

          get_ws_auth(@session, suffix: "view/ws?#{ContainerTicket::PARAM}=#{CGI.escape(ticket)}")
          assert_response :unauthorized

          get_ws_auth(@session, suffix: "view/ws?#{ContainerTicket::PARAM}=forged")
          assert_response :unauthorized
        end

        test "a ticket grants no more than its user's own access" do
          ticket = ContainerTicket.issue(user: @member, session: @session)

          get_ws_auth(@session, suffix: "tty/ws?#{ContainerTicket::PARAM}=#{CGI.escape(ticket)}")

          assert_response :forbidden
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
