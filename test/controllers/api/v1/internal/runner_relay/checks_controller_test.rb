# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Internal
      module RunnerRelay
        # POST /api/v1/internal/runner_relay/checks (runner-relay.md §8.2, §8.3).
        class ChecksControllerTest < ActionDispatch::IntegrationTest
          TOKEN = "relay-internal-token-of-32-characters"

          setup do
            Settings.runners.relay.stubs(:internal_token).returns(TOKEN)
            @company = create(:company)
            @runner = create(:runner, :manual, company: @company)
            @machine = create(:runner_environment, runner: @runner)
            @session = create(:runner_session, environment: @machine, state: "ready")
            @machine.update!(current_session_id: @session.id)
          end

          test "a registered machine that holds its ready session of a live runner with the flag on is valid" do
            assert_equal [ true ], check(@machine, @session)
          end

          test "the answers are in the order of the questions" do
            other = create(:runner_environment, runner: @runner)

            assert_equal [ false, true, false ],
                         check([ other, @session ], [ @machine, @session ], [ @machine, @session.id + 1 ])
          end

          test "a machine that does not exist is not valid, nor is a session that is not an id" do
            assert_equal [ false ], check_raw([ { "environment_id" => 0, "session_id" => @session.id } ])
            assert_equal [ false ], check_raw([ { "environment_id" => @machine.id, "session_id" => nil } ])
            assert_equal [ false ], check_raw([ { "environment_id" => @machine.id, "session_id" => "#{@session.id}" } ])
          end

          test "a machine that no longer holds the session is not valid" do
            @machine.update!(current_session_id: nil)

            assert_equal [ false ], check(@machine, @session)
          end

          test "a machine that is not registered is not valid" do
            @machine.update_columns(state: "failed")

            assert_equal [ false ], check(@machine, @session)
          end

          test "a session that is not ready is not valid" do
            @session.update_columns(state: "finishing")

            assert_equal [ false ], check(@machine, @session)
          end

          test "a machine of a revoked runner is not valid" do
            @runner.update_columns(status: "revoked")

            assert_equal [ false ], check(@machine, @session)
          end

          test "a machine of a deleted runner is not valid" do
            @runner.update_columns(deleted_at: Time.current)

            assert_equal [ false ], check(@machine, @session)
          end

          test "a machine of a company whose external_runners flag is off is not valid" do
            assert_equal [ false ], check_raw([ { "environment_id" => @machine.id, "session_id" => @session.id } ], flag: false)
          end

          test "an empty list is answered with an empty list" do
            assert_equal [], check_raw([])
          end

          test "a body that is not a list of machines is refused" do
            [ nil, "x", [ 1 ], [ { "session_id" => 1 } ], [ { "environment_id" => "7" } ] ].each do |machines|
              post_checks(machines)

              assert_response :unprocessable_entity, machines.inspect
            end
          end

          test "a missing or wrong token is refused, and nothing is checked" do
            Runners::RelayChecks.expects(:valid).never
            [ nil, "Bearer wrong", "Bearer #{TOKEN}x" ].each do |header|
              post_checks([], header)

              assert_response :unauthorized, header.inspect
            end
          end

          private

          def check(*pairs)
            pairs = [ pairs ] if pairs.first.is_a?(RunnerEnvironment)
            check_raw(pairs.map { |environment, session| { "environment_id" => environment.id, "session_id" => session.respond_to?(:id) ? session.id : session } })
          end

          def post_checks(machines, authorization = "Bearer #{TOKEN}")
            post "/api/v1/internal/runner_relay/checks", params: { machines: machines }, as: :json,
                                                         headers: { "Authorization" => authorization }.compact
          end

          # The company's external_runners flag is on unless a test says otherwise.
          def check_raw(machines, flag: true)
            with_feature(:external_runners, flag, company: @company) { post_checks(machines) }

            assert_response :success
            response.parsed_body["machines"]
          end
        end
      end
    end
  end
end
