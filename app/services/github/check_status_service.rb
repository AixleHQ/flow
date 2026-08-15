# frozen_string_literal: true

module Github
  # Read-only adapter over the GitHub CI status endpoints, used to reconcile CI
  # gates whose resolving webhook never arrived (see `GateReconciler`).
  #
  # It answers exactly the question a gate asks — "is the thing I am waiting on
  # finished, and how did it end?" — and answers it in the app's own vocabulary
  # (`Ci::ProbeResult`) rather than leaking Octokit resources upward. Three
  # distinguishable answers matter to the caller:
  #
  #   - completed    → the provider has a verdict; the gate can resolve with it
  #   - in_progress  → still running; the webhook may yet arrive, leave it alone
  #   - unresolvable → the run/PR/repo cannot be read at all (deleted, renamed,
  #                    never existed, no longer visible to the installation), so
  #                    NO webhook can ever resolve this gate
  #
  # Anything else that goes wrong (rate limit, 5xx, an unusable installation
  # token) is `unavailable`: transient, retried on the next sweep, and bounded by
  # the gate's TTL rather than by pretending to know the outcome.
  class CheckStatusService
    def initialize(integration)
      @integration = integration
    end

    # Combined state of every check suite on a pull request's head commit — the
    # reconciliation equivalent of the `check_suite` webhook the gate waits for.
    #
    # A PR with no check suites at all is `unresolvable`: nothing is running, so
    # no completion event is coming.
    def pull_request_checks(repo_full_name, pr_number)
      pr = client.pull_request(repo_full_name, pr_number)
      head_sha = pr[:head][:sha]

      suites = Array(client.check_suites_for_ref(repo_full_name, head_sha)[:check_suites])
      return unresolvable("no check suites on #{repo_full_name}@#{head_sha[0, 7]} for PR ##{pr_number}") if suites.empty?

      pending = suites.reject { |suite| suite[:status].to_s == "completed" }
      if pending.any?
        return Ci::ProbeResult.in_progress(
          "#{pending.size}/#{suites.size} check suites still running on PR ##{pr_number}"
        )
      end

      conclusion = worst_conclusion(suites.map { |suite| suite[:conclusion] })
      Ci::ProbeResult.completed(
        conclusion,
        "#{suites.size} check suite(s) completed on PR ##{pr_number}"
      )
    rescue Octokit::NotFound
      unresolvable("PR ##{pr_number} not found in #{repo_full_name}")
    rescue Octokit::Error, Github::TokenService::ConfigurationError,
           Github::TokenService::AuthenticationError => e
      unavailable(e)
    end

    # State of a single GitHub Actions workflow run.
    def workflow_run_status(repo_full_name, run_id)
      run = client.workflow_run(repo_full_name, run_id)

      unless run[:status].to_s == "completed"
        return Ci::ProbeResult.in_progress("workflow run #{run_id} is #{run[:status]}")
      end

      Ci::ProbeResult.completed(
        run[:conclusion],
        "workflow run #{run_id} completed"
      )
    rescue Octokit::NotFound
      unresolvable("workflow run #{run_id} not found in #{repo_full_name}")
    rescue Octokit::Error, Github::TokenService::ConfigurationError,
           Github::TokenService::AuthenticationError => e
      unavailable(e)
    end

    private

    def client
      @client ||= Octokit::Client.new(access_token: installation_token)
    end

    def installation_token
      Github::TokenService.new(@integration).generate_installation_token
    end

    # One failing suite fails the commit — GitHub's own "checks" verdict on a PR
    # is the same reduction, and resolving the gate as `success` because a LATER
    # suite passed would be exactly the silent bypass this reconciliation exists
    # to avoid.
    def worst_conclusion(conclusions)
      # A completed suite with no conclusion is reported as such rather than
      # normalised into one: "unknown" is not in Gate::PASSING_CONCLUSIONS, so it
      # cannot read as a pass, and it does not invent a failure that GitHub never
      # reported either.
      values = conclusions.map { |c| c.to_s.presence || "unknown" }
      values.find { |c| !Gate::PASSING_CONCLUSIONS.include?(c) } || values.first || "success"
    end

    def unresolvable(detail)
      Ci::ProbeResult.unresolvable(detail)
    end

    def unavailable(error)
      Rails.logger.warn("[Github::CheckStatusService] #{error.class}: #{error.message}")
      Ci::ProbeResult.unavailable("#{error.class}: #{error.message}")
    end
  end
end
