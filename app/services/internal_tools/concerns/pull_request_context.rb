# frozen_string_literal: true

module InternalTools
  module Concerns
    # Target resolution, authorization and the operation ledger shared by every
    # pull_request_* tool (docs/design/bitbucket-integration.md §4.7–4.10).
    # Provider specifics stay behind PullRequests::Provider.
    #
    # `requires_integration :pull_requests` only says some GitHub, GitLab or Bitbucket
    # connection exists in the project. Whether THIS call may touch THIS
    # repository is decided here: the repository must be attached to the
    # session, and its connection must belong to the session's project.
    module PullRequestContext
      extend ActiveSupport::Concern

      REPOSITORY_PARAM = "Aixle repository id (the ID column of the repositories table in your context). " \
                         "Optional when this session holds a single GitHub, GitLab or Bitbucket repository, or when " \
                         "`pull_request` is a URL."
      PULL_REQUEST_PARAM = "The pull request (a GitLab merge request): its number or browser URL."
      OPERATION_KEY_PARAM = "Optional idempotency key. Reusing it for the same request replays the first result " \
                            "instead of writing twice; an identical retry in this session is recognised without one."
      UNAVAILABLE = "No GitHub, GitLab or Bitbucket connection in this project. Connect one under Project Settings → " \
                    "Integrations and attach its repository."
      LIMIT_PARAM = "Page size, 1–100."
      CURSOR_PARAM = "`next_cursor` from the previous page."

      private

      def pull_request_guard
        yield
      rescue PullRequests::Error => e
        error(e.to_h.to_json)
      rescue PullRequestOperation::Conflict => e
        error({ error: "conflict", message: e.message }.to_json)
      end

      # [repository, provider] for this call.
      def resolve_target!(ref: params[:pull_request])
        repository = resolve_repository!(ref)
        integration = repository.integration
        verify_connection!(integration)
        [ repository, PullRequests::Provider.for(integration) ]
      end

      def resolve_repository!(ref)
        return requested_repository! if params[:repository_id].present?

        candidates = capable_repositories
        if ref.to_s.match?(%r{\Ahttps?://}i)
          owners = candidates.select { |repo| PullRequests::Provider.for(repo.integration).owns_reference?(repo, ref) }
          return owners.first if owners.one?
        end
        return candidates.first if candidates.one?

        raise PullRequests::Error.new(
          candidates.empty? ? "This session has no GitHub, GitLab or Bitbucket repository attached" :
                              "repository_id is required — this session holds #{candidates.size} repositories with pull requests",
          code: "repository_required",
          details: { candidates: candidates.map { |repo| { repository_id: repo.id, full_name: repo.full_name } } }
        )
      end

      def requested_repository!
        id = params[:repository_id]
        repository = session&.repositories&.includes(:integration)&.find_by(id: id)
        raise PullRequests::Error.new("Repository #{id} is not attached to this session", code: "not_authorized") unless repository
        unless capable?(repository)
          raise PullRequests::Error.new("Repository #{id} is not on a host with pull_request_* tools " \
                                        "(GitHub, GitLab or Bitbucket)", code: "validation_failed")
        end

        repository
      end

      def capable_repositories
        return [] if session.nil?

        session.repositories.includes(:integration).select { |repo| capable?(repo) }.sort_by(&:id)
      end

      def capable?(repository) = repository.integration.present? && PullRequests.provider?(repository.integration.provider)

      # A connection from another project — or another company — is out of
      # reach even when one of its repositories was attached to this session.
      def verify_connection!(integration)
        same_tenant = integration.company_id == project&.company_id &&
                      (integration.project_id.nil? || integration.project_id == project&.id)
        raise PullRequests::Error.new("That connection belongs to another project", code: "not_authorized") unless same_tenant
        return if integration.active?

        raise PullRequests::Error.new("The #{integration.provider.to_s.titleize} connection '#{integration.name}' " \
                                      "needs attention on the Integrations page", code: "integration_unavailable")
      end

      def respond(value)
        success(value.as_json.to_json)
      end

      def page_limit
        params[:limit].present? ? params[:limit].to_i.clamp(1, 100) : 20
      end

      # Claims the ledger row before the provider call, so a retry is recognised.
      # A failed claim may be retried — the provider refused it, nothing was
      # written — but an unknown one may not: it may have landed.
      def with_write(repository, operation, payload, number: nil)
        key = params[:operation_key].presence || automatic_key(operation, payload)
        record, state = PullRequestOperation.claim!(integration: repository.integration, repository: repository, key: key,
                                                    operation: operation, payload: payload,
                                                    pull_request_number: number&.to_s, **run_attribution)
        return replayed(record) if state == :replayed && !record.failed?

        record.retry! if record.failed?
        value = yield
        result = value.as_json
        record.succeed!(result, pull_request_number: number || result_number(result))
        success(result.merge("operation_key" => key).to_json)
      rescue PullRequests::Error::OutcomeUnknown => e
        record&.unknown!
        error({ error: "outcome_unknown", operation_key: key,
                message: "#{e.message}. The request may have been applied — read the pull request before " \
                         "retrying; reissuing it can create a duplicate." }.to_json)
      rescue PullRequests::Error => e
        record&.fail!(e.code)
        error(e.to_h.merge(operation_key: key).to_json)
      end

      def automatic_key(operation, payload)
        "auto-" + Digest::SHA256.hexdigest([ session&.id, operation, PullRequestOperation.digest_for(payload) ].join(":"))[0, 40]
      end

      def run_attribution
        { terminal_session_id: session&.id, user_id: session&.user_id,
          workflow_run_id: workflow_run&.id, workflow_id: workflow_run&.workflow_id }
      end

      # The issue a tracker event started this run for, by the reference Jira and
      # the code hosts link branches and pull requests with: its key, else its id.
      def tracker_issue_key
        issue = workflow_run&.shared_context.to_h.dig("tracker", "issue").to_h
        (issue["key"].presence || issue["id"]).presence&.to_s
      end

      def result_number(result)
        result["number"] || result.dig("pull_request", "number")
      end

      def replayed(record)
        case record.state.to_s
        when "succeeded"
          success(record.result.merge("operation_key" => record.operation_key, "replayed" => true).to_json)
        when "unknown"
          error({ error: "outcome_unknown", operation_key: record.operation_key,
                  message: "This request was sent earlier and never confirmed. Read the pull request before " \
                           "retrying." }.to_json)
        else
          error({ error: "operation_in_flight", operation_key: record.operation_key,
                  message: "This request is still being processed." }.to_json)
        end
      end
    end
  end
end
