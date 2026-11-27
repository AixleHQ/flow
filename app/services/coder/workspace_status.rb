# frozen_string_literal: true

module Coder
  # WorkspaceStatus — what a Coder workspace is doing, read from its last build
  # and its agents. One classification for every consumer of the integration
  # (the allocator, the dead-workspace reaper, a runner), so they cannot
  # disagree about what "running" means.
  #
  # `state`, from the workspace's LAST BUILD:
  #
  #   * `building`  — a start or stop build is in flight
  #   * `running`   — the last build is a succeeded start
  #   * `stopped`   — nothing is running and a start is needed: a succeeded
  #                   stop, a cancelled build, or no build at all
  #   * `deleting`  — a delete build is in flight
  #   * `deleted`   — a succeeded delete, or a workspace Coder no longer knows
  #   * `failed`    — the last build failed, whatever its transition
  #
  # `agent`, from the agents the build reports (`HealthCheck` owns the rule for
  # a broken one):
  #
  #   * `disconnected` — every agent is explicitly bad (`HealthCheck.agents_unhealthy?`)
  #   * `connected`    — at least one agent is connected and not reporting unhealthy
  #   * `none`         — no signal either way: no agents reported, or they are
  #                      still connecting. Absence is not evidence (§ D-0).
  #
  # `running` says nothing about the box being usable: it is the last build, as
  # the Coder API has no other word for it.
  WorkspaceStatus = Data.define(:state, :agent, :transition, :build_id, :error) do
    class << self
      # `workspace` is a workspace hash of Coder's API, or nil for a workspace
      # Coder no longer knows (which is a deleted one).
      def from(workspace)
        return new(state: :deleted, agent: :none, transition: "delete", build_id: nil, error: nil) if workspace.nil?

        build      = workspace["latest_build"].is_a?(Hash) ? workspace["latest_build"] : {}
        transition = build["transition"].to_s
        job        = build.dig("job", "status").to_s

        new(
          state:      state_of(transition, job),
          agent:      agent_of(workspace),
          transition: transition,
          build_id:   build["id"].presence&.to_s,
          error:      build.dig("job", "error").to_s.strip.presence
        )
      end

      private

      def state_of(transition, job)
        return :failed if job == "failed"

        in_flight = %w[pending running canceling].include?(job)
        case transition
        when "delete" then return :deleted if job == "succeeded"
        when "start"  then return :running if job == "succeeded"
        end

        in_flight ? (transition == "delete" ? :deleting : :building) : :stopped
      end

      def agent_of(workspace)
        return :disconnected if Coder::HealthCheck.agents_unhealthy?(workspace)

        resources = workspace.dig("latest_build", "resources")
        agents = resources.is_a?(Array) ? resources.flat_map { |r| r.is_a?(Hash) ? Array(r["agents"]) : [] } : []
        connected = agents.any? { |a| a.is_a?(Hash) && a["status"].to_s == "connected" && a.dig("health", "healthy") != false }
        connected ? :connected : :none
      end
    end

    def running?   = state == :running
    def building?  = state == :building
    def stopped?   = state == :stopped
    def deleting?  = state == :deleting
    def deleted?   = state == :deleted
    def failed?    = state == :failed
    def connected? = agent == :connected
  end
end
