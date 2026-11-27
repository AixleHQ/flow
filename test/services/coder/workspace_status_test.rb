# frozen_string_literal: true

require "test_helper"

module Coder
  class WorkspaceStatusTest < ActiveSupport::TestCase
    def workspace(transition:, job:, agents: nil, error: nil, id: "b1")
      build = { "id" => id, "transition" => transition, "job" => { "status" => job } }
      build["job"]["error"] = error if error
      build["resources"] = [ { "agents" => agents } ] unless agents.nil?
      { "id" => "u1", "name" => "aixle-prod-1", "latest_build" => build }
    end

    def state_of(transition, job) = Coder::WorkspaceStatus.from(workspace(transition: transition, job: job)).state

    test "a succeeded start is running" do
      assert_equal :running, state_of("start", "succeeded")
    end

    test "a start in flight is building" do
      %w[pending running canceling].each { |job| assert_equal :building, state_of("start", job), job }
    end

    test "a stop in flight is building, a succeeded stop is stopped" do
      assert_equal :building, state_of("stop", "running")
      assert_equal :stopped, state_of("stop", "succeeded")
    end

    test "a cancelled build needs a start" do
      assert_equal :stopped, state_of("start", "canceled")
      assert_equal :stopped, state_of("stop", "canceled")
    end

    test "a delete in flight is deleting and a succeeded delete is deleted" do
      assert_equal :deleting, state_of("delete", "pending")
      assert_equal :deleting, state_of("delete", "running")
      assert_equal :deleted, state_of("delete", "succeeded")
    end

    test "a failed build is failed whatever its transition" do
      %w[start stop delete].each { |transition| assert_equal :failed, state_of(transition, "failed"), transition }
    end

    test "a workspace with no build is stopped" do
      assert_equal :stopped, Coder::WorkspaceStatus.from({ "id" => "u1" }).state
    end

    test "a workspace Coder does not know is deleted" do
      status = Coder::WorkspaceStatus.from(nil)

      assert status.deleted?
      assert_equal :none, status.agent
    end

    test "it carries the transition, the build id and the provisioner's error" do
      status = Coder::WorkspaceStatus.from(workspace(transition: "start", job: "failed", error: " no capacity ", id: "b9"))

      assert_equal "start", status.transition
      assert_equal "b9", status.build_id
      assert_equal "no capacity", status.error
    end

    test "agents that all disconnect or time out are disconnected" do
      [ "disconnected", "timeout" ].each do |agent_status|
        status = Coder::WorkspaceStatus.from(
          workspace(transition: "start", job: "succeeded", agents: [ { "status" => agent_status } ])
        )
        assert_equal :disconnected, status.agent, agent_status
      end
    end

    test "an agent reporting itself unhealthy is disconnected, as the health check reads it" do
      status = Coder::WorkspaceStatus.from(
        workspace(transition: "start", job: "succeeded",
                  agents: [ { "status" => "connected", "health" => { "healthy" => false } } ])
      )

      assert_equal :disconnected, status.agent
    end

    test "a connected agent is connected" do
      status = Coder::WorkspaceStatus.from(
        workspace(transition: "start", job: "succeeded", agents: [ { "status" => "connected" } ])
      )

      assert_equal :connected, status.agent
      assert status.connected?
    end

    test "one connected agent among disconnected ones is connected" do
      status = Coder::WorkspaceStatus.from(
        workspace(transition: "start", job: "succeeded",
                  agents: [ { "status" => "disconnected" }, { "status" => "connected" } ])
      )

      assert_equal :connected, status.agent
    end

    test "no agents, or agents still connecting, give no signal" do
      [ nil, [], [ { "status" => "connecting" } ], [ { "status" => "created" } ] ].each do |agents|
        status = Coder::WorkspaceStatus.from(workspace(transition: "start", job: "succeeded", agents: agents))
        assert_equal :none, status.agent, agents.inspect
      end
    end
  end
end
