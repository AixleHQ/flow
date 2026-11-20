# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Internal
      module RunnerRelay
        # GET /api/v1/internal/runner_relay/holders/:route_token (runner-relay.md §8.2).
        class HoldersControllerTest < ActionDispatch::IntegrationTest
          TOKEN = "relay-internal-token-of-32-characters"

          setup do
            Settings.runners.relay.stubs(:internal_token).returns(TOKEN)
            @runner = create(:runner, :manual)
            @machine = create(:runner_environment, runner: @runner)
            @session = create(:runner_session, environment: @machine, state: "ready")
            @machine.update!(current_session_id: @session.id)
          end

          test "answers the session, the machine that holds it, its state and its ports" do
            authorize

            show(@session.route_token)

            assert_response :success
            assert_equal({ "session_id" => @session.id, "environment_id" => @machine.id, "state" => "ready",
                           "ports" => Runners::Tunnel.ports(@session) }, response.parsed_body)
          end

          test "answers a null machine for a session no machine holds" do
            @machine.update!(current_session_id: nil)
            authorize

            show(@session.route_token)

            assert_response :success
            assert_nil response.parsed_body["environment_id"]
          end

          test "answers 404 for a token no session has" do
            authorize

            show("0" * 32)

            assert_response :not_found
          end

          test "answers 404 for a hosted session's token" do
            hosted = create(:terminal_session, state: "ready")
            authorize

            show(hosted.route_token)

            assert_response :not_found
          end

          test "refuses a request without the token" do
            show(@session.route_token)

            assert_response :unauthorized
          end

          test "refuses a wrong token, and a token of another shape" do
            [ "Bearer wrong", "Bearer #{TOKEN}x", TOKEN, "Basic #{TOKEN}", "Bearer " ].each do |header|
              show(@session.route_token, header)

              assert_response :unauthorized, header
            end
          end

          test "refuses every request while the platform has no token" do
            Settings.runners.relay.stubs(:internal_token).returns("")

            show(@session.route_token, "Bearer ")

            assert_response :unauthorized
          end

          private

          def authorize
            @authorization = "Bearer #{TOKEN}"
          end

          def show(route_token, authorization = @authorization)
            get "/api/v1/internal/runner_relay/holders/#{route_token}", headers: { "Authorization" => authorization }.compact
          end
        end
      end
    end
  end
end
