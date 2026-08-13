# frozen_string_literal: true

require "test_helper"

module Coder
  class HealthCheckTest < ActiveSupport::TestCase
    # Stands in for Coder::SshRunner (app-owned adapter, injected through the
    # constructor seam) so the probe's decision logic can be exercised without
    # a `coder` CLI.
    class FakeRunner
      attr_reader :calls

      def initialize(result: nil, raises: nil)
        @result = result
        @raises = raises
        @calls  = []
      end

      def exec(workspace_name:, command:, timeout: nil, **)
        @calls << { workspace_name: workspace_name, command: command, timeout: timeout }
        raise @raises if @raises

        @result
      end
    end

    setup do
      @company     = create(:company)
      @user        = create(:user, :admin, company: @company)
      @integration = create(:integration, :coder, :active, company: @company, connected_by: @user)
    end

    def workspace_with_agents(agents)
      { "name" => "ws-1", "latest_build" => { "resources" => [ { "agents" => agents } ] } }
    end

    def probe_output(load:, cores:)
      { exit_code: 0, stdout: "aixle_probe load=#{load} cores=#{cores}\n", stderr: "", truncated: false }
    end

    # ---------- passive tier ----------

    test "rejects a workspace whose every agent is reported unhealthy" do
      ws = workspace_with_agents([ { "status" => "connected", "health" => { "healthy" => false } } ])

      assert Coder::HealthCheck.agents_unhealthy?(ws)
      assert_match(/coder agent reports/, Coder::HealthCheck.unhealthy_reason(ws))
    end

    test "rejects a workspace whose agent is disconnected" do
      ws = workspace_with_agents([ { "status" => "disconnected" } ])

      assert Coder::HealthCheck.agents_unhealthy?(ws)
    end

    test "keeps a workspace when at least one agent is healthy" do
      ws = workspace_with_agents([
        { "status" => "disconnected" },
        { "status" => "connected", "health" => { "healthy" => true } }
      ])

      assert_not Coder::HealthCheck.agents_unhealthy?(ws)
    end

    # The degradation contract: every box in the field today comes from a
    # template that predates this work, so a missing or unfamiliar signal must
    # never read as a rejection.
    test "keeps a workspace that reports no agent data at all" do
      assert_not Coder::HealthCheck.agents_unhealthy?({ "name" => "ws-1" })
      assert_not Coder::HealthCheck.agents_unhealthy?({ "name" => "ws-1", "latest_build" => {} })
      assert_not Coder::HealthCheck.agents_unhealthy?(workspace_with_agents([]))
      assert_nil Coder::HealthCheck.unhealthy_reason(workspace_with_agents([]))
    end

    test "keeps a workspace whose agent status is transient or unrecognised" do
      assert_not Coder::HealthCheck.agents_unhealthy?(workspace_with_agents([ { "status" => "connecting" } ]))
      assert_not Coder::HealthCheck.agents_unhealthy?(workspace_with_agents([ { "status" => "some_future_state" } ]))
    end

    # ---------- active tier ----------

    test "reports healthy when load is within the ceiling" do
      runner = FakeRunner.new(result: probe_output(load: "1.20", cores: 4))
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.healthy?
      assert_in_delta 1.2, verdict.load
      assert_equal 4, verdict.cores
    end

    test "reports sick when load is over cores times the factor" do
      runner = FakeRunner.new(result: probe_output(load: "84.34", cores: 4))
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.sick?
      assert_match(/load average 84.34/, verdict.reason)
    end

    test "reports sick when the probe times out" do
      runner = FakeRunner.new(result: { exit_code: 124, stdout: "", stderr: "coder ssh: timed out", truncated: false })
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.sick?
      assert_match(/did not answer/, verdict.reason)
    end

    # A missing CLI is our fault, not the workspace's — quarantining on it
    # would empty every pool at once.
    test "reports unknown when the probe cannot run on our side" do
      runner = FakeRunner.new(result: { exit_code: 127, stdout: "", stderr: "command not found", truncated: false })
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.unknown?
      assert_match(/coder CLI missing/, verdict.reason)
    end

    test "reports unknown when the token cannot be resolved" do
      runner = FakeRunner.new(raises: Coder::TokenService::AuthenticationError.new("401"))
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.unknown?
    end

    test "treats a reachable workspace with unparseable probe output as healthy" do
      runner = FakeRunner.new(result: { exit_code: 0, stdout: "BusyBox v1.36\n", stderr: "", truncated: false })
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.healthy?
    end

    test "skips the load verdict when the workspace has no loadavg or nproc" do
      runner = FakeRunner.new(result: { exit_code: 0, stdout: "aixle_probe load= cores=\n", stderr: "", truncated: false })
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.healthy?
      assert_match(/load unknown/, verdict.reason)
    end

    # `reachable` is what separates "alive but drowning" from "gone". Both are
    # `sick`; only the second may be reaped.
    test "an overloaded workspace is sick but reachable" do
      runner = FakeRunner.new(result: probe_output(load: "84.34", cores: 4))
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.sick?
      assert verdict.reachable?
      assert_not verdict.unreachable?
    end

    test "a workspace that never answers is sick and unreachable" do
      runner = FakeRunner.new(result: { exit_code: 124, stdout: "", stderr: "coder ssh: timed out", truncated: false })
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.unreachable?
      assert_not verdict.reachable?
    end

    test "a failure on our side leaves reachability unknown, neither reachable nor unreachable" do
      [
        FakeRunner.new(result: { exit_code: 127, stdout: "", stderr: "command not found", truncated: false }),
        FakeRunner.new(raises: Coder::TokenService::AuthenticationError.new("401"))
      ].each do |runner|
        verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

        assert_not verdict.reachable?
        assert_not verdict.unreachable?
        assert_nil verdict.reachable
      end
    end

    test "a healthy workspace is reachable" do
      runner = FakeRunner.new(result: probe_output(load: "1.20", cores: 4))
      verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

      assert verdict.reachable?
    end

    test "reports unknown and does not probe when health probing is disabled" do
      runner = FakeRunner.new(result: probe_output(load: "0.1", cores: 4))

      original = Settings.coder.health_probe_enabled
      Settings.coder.health_probe_enabled = false
      begin
        verdict = Coder::HealthCheck.new(@integration, ssh_runner: runner).probe(workspace_name: "ws-1")

        assert verdict.unknown?
        assert_empty runner.calls
      ensure
        Settings.coder.health_probe_enabled = original
      end
    end
  end
end
