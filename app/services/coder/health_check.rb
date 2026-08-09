# frozen_string_literal: true

module Coder
  # HealthCheck — decides whether a Coder workspace is fit to hand to a session.
  #
  # The governing rule (design doc § D-0, "degradation contract") is that a
  # workspace is rejected only on POSITIVE EVIDENCE that it is sick. Absence of
  # a signal is never evidence: a box from a template that predates this work
  # reports no agent health, may not answer the probe the way we expect, and
  # must still allocate exactly as it does today. Getting this backwards would
  # empty every pool at once, which is a worse outage than the one this fixes.
  #
  # Two tiers:
  #
  #   * passive — reads the agent data already present in the workspace list
  #     response. Zero extra API calls. Rejects only when every agent
  #     explicitly says it is disconnected or unhealthy.
  #   * active  — one short SSH round trip after the lock is taken. Rejects an
  #     unresponsive box (the probe times out) and an overloaded one (1-minute
  #     load above `cores * load_factor`). A probe that fails for a reason on
  #     OUR side (no `coder` CLI in the Rails image, auth failure) returns
  #     `:unknown`, which the allocator treats as "keep the candidate".
  class HealthCheck
    # Emitted on one line so parsing does not depend on `uptime`'s wildly
    # platform-dependent wording. Both values are optional: a box without
    # /proc/loadavg or nproc still reports reachability, it just skips the
    # load verdict.
    PROBE_COMMAND = <<~SH.strip
      load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo ""); cores=$(nproc 2>/dev/null || echo ""); echo "aixle_probe load=$load cores=$cores"
    SH

    PROBE_MARKER = "aixle_probe"

    Result = Struct.new(:state, :reason, :load, :cores, keyword_init: true) do
      def healthy? = state == :healthy
      def sick?    = state == :sick
      def unknown? = state == :unknown
    end

    class << self
      # Passive tier. True only when the response carries agent data AND every
      # agent in it is explicitly bad. `nil`, `[]`, or a shape we do not
      # recognise means "no signal", which is not a rejection.
      def agents_unhealthy?(workspace)
        agents = agents_in(workspace)
        return false if agents.empty?

        agents.all? { |agent| agent_unhealthy?(agent) }
      end

      def unhealthy_reason(workspace)
        agents = agents_in(workspace)
        return nil if agents.empty?

        statuses = agents.map { |a| a["status"].presence || "unknown" }.uniq
        "coder agent reports #{statuses.join(', ')}"
      end

      private

      # Only states Coder asserts as broken. Transient ones (`connecting`,
      # `created`, `starting`) and anything a future Coder version invents are
      # deliberately absent: an unrecognised status must read as "no signal",
      # not as a rejection, or a vocabulary change upstream empties the pool.
      BAD_AGENT_STATUSES = %w[disconnected timeout].freeze

      def agents_in(workspace)
        resources = workspace.dig("latest_build", "resources")
        return [] unless resources.is_a?(Array)

        resources.flat_map { |r| r.is_a?(Hash) ? Array(r["agents"]) : [] }.select { |a| a.is_a?(Hash) }
      end

      def agent_unhealthy?(agent)
        return true if agent.dig("health", "healthy") == false

        BAD_AGENT_STATUSES.include?(agent["status"].to_s)
      end
    end

    def initialize(integration, ssh_runner: nil)
      @integration = integration
      @ssh_runner  = ssh_runner || Coder::SshRunner.new(integration)
    end

    def enabled?
      Settings.coder&.health_probe_enabled != false
    end

    # Active tier. Never raises: every failure path resolves to a Result, and
    # anything we cannot attribute to the workspace resolves to :unknown.
    def probe(workspace_name:)
      return Result.new(state: :unknown, reason: "health probe disabled") unless enabled?

      result = @ssh_runner.exec(
        workspace_name: workspace_name,
        command:        PROBE_COMMAND,
        timeout:        probe_timeout
      )

      case result[:exit_code]
      when 0   then evaluate(result[:stdout].to_s)
      when 124 then Result.new(state: :sick,    reason: "did not answer a #{probe_timeout}s probe")
      when 127 then Result.new(state: :unknown, reason: "coder CLI missing from the Rails image")
      else          Result.new(state: :sick,    reason: probe_failure_reason(result))
      end
    rescue Coder::SshRunner::CommandError,
           Coder::TokenService::AuthenticationError,
           Coder::TokenService::ConfigurationError => e
      # Our side, not the workspace's. Keeping the candidate is the whole point
      # of the degradation contract.
      Result.new(state: :unknown, reason: "probe could not run: #{e.class.name.demodulize}")
    end

    private

    def evaluate(stdout)
      return Result.new(state: :healthy, reason: "reachable; probe output unrecognised") unless stdout.include?(PROBE_MARKER)

      load  = stdout[/load=([0-9.]+)/, 1]&.to_f
      cores = stdout[/cores=(\d+)/, 1]&.to_i

      return Result.new(state: :healthy, reason: "reachable; load unknown", load: load, cores: cores) if load.nil? || cores.nil? || cores.zero?

      ceiling = cores * load_factor
      if load > ceiling
        Result.new(
          state:  :sick,
          reason: "load average #{load} over #{format('%.1f', ceiling)} (#{cores} cores)",
          load:   load,
          cores:  cores
        )
      else
        Result.new(state: :healthy, reason: "load #{load} on #{cores} cores", load: load, cores: cores)
      end
    end

    def probe_failure_reason(result)
      detail = result[:stderr].to_s.strip
      detail = result[:stdout].to_s.strip if detail.empty?
      detail = detail.byteslice(0, 200).to_s
      "probe exited #{result[:exit_code]}#{detail.empty? ? '' : ": #{detail}"}"
    end

    def probe_timeout
      (Settings.coder&.health_probe_timeout || 15).to_i
    end

    def load_factor
      (Settings.coder&.health_load_factor || 2.0).to_f
    end
  end
end
