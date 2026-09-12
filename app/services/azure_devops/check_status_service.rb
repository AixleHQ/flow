# frozen_string_literal: true

module AzureDevops
  # The reconciliation side of Azure CI gates: what a gate's build or pull
  # request actually looks like right now, in the vocabulary `Ci::ProbeResult`
  # speaks.
  #
  # Exists because webhooks are the happy path and nothing more. Azure puts a
  # failing subscription on probation and stops delivering to it, so "no event
  # arrived" and "nothing happened" are indistinguishable from here — and a gate
  # that no delivery will ever resolve would block its task forever.
  class CheckStatusService
    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    def build_status(build_id, expected_commit: nil)
      build = BuildService.new(integration).get(build_id)
      return Ci::ProbeResult.in_progress("build #{build_id} is #{build[:status]}") unless build[:status].to_s == "completed"

      if expected_commit.present? && build[:commit].present? && build[:commit] != expected_commit
        # A verdict about a different commit is not evidence about this gate.
        return Ci::ProbeResult.in_progress(
          "build #{build_id} ran against #{build[:commit]}, not the expected #{expected_commit}"
        )
      end

      # `result` is the verdict and it is reported verbatim. A completed build
      # with no result is not a pass, and Gate::PASSING_CONCLUSIONS decides.
      Ci::ProbeResult.completed(build[:result], "build #{build[:build_number] || build_id}")
    rescue NotFound
      Ci::ProbeResult.unresolvable("build #{build_id} no longer exists or is not visible to this connection")
    rescue PermissionDenied
      Ci::ProbeResult.unresolvable("this connection may not read builds — enable the builds.read capability")
    rescue Error => e
      Ci::ProbeResult.unavailable("#{e.code}")
    end

    def pull_request_policies(repository, pull_request_id, expected_commit: nil)
      policies = BuildService.new(integration).policy_evaluations(repository, pull_request_id)
      if policies[:blocking_count].to_i.zero?
        # Nothing can block this pull request, so nothing will ever report on it.
        # Better to say that than to leave the gate waiting on a verdict that has
        # no source.
        return Ci::ProbeResult.unresolvable("pull request #{pull_request_id} has no blocking branch policies")
      end

      if expected_commit.present?
        current = PullRequestService.new(integration).get(repository, pull_request_id)
        if current[:last_merge_source_commit].present? && current[:last_merge_source_commit] != expected_commit
          return Ci::ProbeResult.in_progress(
            "pull request #{pull_request_id} has moved to #{current[:last_merge_source_commit]}"
          )
        end
      end

      return Ci::ProbeResult.completed("approved", "all blocking policies approved") if policies[:all_blocking_satisfied]

      Ci::ProbeResult.in_progress("waiting on #{policies[:unsatisfied].join(', ').presence || 'branch policies'}")
    rescue NotFound
      Ci::ProbeResult.unresolvable("pull request #{pull_request_id} no longer exists or is not visible")
    rescue PermissionDenied
      Ci::ProbeResult.unresolvable("this connection may not read branch policies")
    rescue Error => e
      Ci::ProbeResult.unavailable("#{e.code}")
    end
  end
end
