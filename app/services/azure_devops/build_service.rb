# frozen_string_literal: true

module AzureDevops
  # Azure Pipelines builds and branch-policy evaluations — the CI half of the
  # parity extension.
  #
  # The two are separate questions and the design keeps them separate on purpose:
  # a green build is not merge eligibility. Branch policies can require reviewers,
  # linked work items, comment resolution and more than one build, so "the build
  # passed" answers a strictly smaller question than "this pull request may
  # complete".
  class BuildService
    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    # `project_id` is required unless the connection covers exactly one project
    # or a repository names it — a build list is project-scoped in Azure, and
    # picking one for the caller would silently answer about the wrong one.
    def list(repository: nil, branch: nil, limit: 25, project_id: nil)
      client, resolved = client_for(project_id: project_id || repository&.external_project_id)
      params = {
        "$top" => limit.to_i.clamp(1, 100),
        queryOrder: "queueTimeDescending",
        repositoryId: repository&.external_id,
        # Azure requires the repository TYPE alongside the id; omitting it makes
        # the repository filter silently do nothing.
        repositoryType: (repository ? "TfsGit" : nil),
        branchName: branch.present? ? qualified_ref(branch) : nil
      }.compact

      payload = client.get("_apis", "build", "builds", family: :build, project: resolved.project_id, params: params)
      Array(payload["value"]).map { |build| summarize(build) }
    end

    # A build id is unique per organization but the endpoint is project-scoped,
    # so with several projects the right one is searched for rather than
    # guessed. `project_id` skips the search when the caller knows it.
    def get(build_id, project_id: nil)
      return fetch_build(build_id, project_id) if project_id.present?

      candidates = integration.azure_project_ids
      return fetch_build(build_id, candidates.first) if candidates.one?

      candidates.each do |candidate|
        found = begin
          fetch_build(build_id, candidate)
        rescue NotFound
          nil
        end
        return found if found
      end
      raise NotFound, "Azure has no build #{build_id} in any project this connection covers"
    end

    # Branch-policy evaluations for one pull request, which is what actually
    # decides completion. The artifact id is the same vstfs identifier the
    # work-item link uses.
    def policy_evaluations(repository, pull_request_id)
      client, resolved = client_for(project_id: repository&.external_project_id)
      artifact_id = "vstfs:///CodeReview/CodeReviewId/#{resolved.project_id}%2F#{pull_request_id}"

      payload = client.get("_apis", "policy", "evaluations",
                           family: :policy, project: resolved.project_id,
                           params: { artifactId: artifact_id })

      evaluations = Array(payload["value"]).map do |evaluation|
        {
          id: evaluation["evaluationId"],
          status: evaluation["status"],
          type: evaluation.dig("configuration", "type", "displayName"),
          blocking: evaluation.dig("configuration", "isBlocking"),
          enabled: evaluation.dig("configuration", "isEnabled")
        }.compact
      end

      blocking = evaluations.select { |e| e[:blocking] && e[:enabled] != false }
      {
        repository_id: repository&.id,
        pull_request_id: pull_request_id.to_i,
        evaluations: evaluations,
        # "Everything that can block is approved." Reported rather than inferred
        # from a build status, because a build is only one of the things a policy
        # set can require.
        all_blocking_satisfied: blocking.any? && blocking.all? { |e| e[:status] == "approved" },
        blocking_count: blocking.size,
        unsatisfied: blocking.reject { |e| e[:status] == "approved" }.map { |e| e[:type] }.compact
      }
    end

    private

    def fetch_build(build_id, project_id)
      client, resolved = client_for(project_id: project_id)
      summarize(client.get("_apis", "build", "builds", build_id.to_s, family: :build, project: resolved.project_id))
    end

    def client_for(project_id: nil)
      CredentialProvider.client_for(integration, capability: :"builds.read", project_id: project_id)
    end

    def qualified_ref(branch)
      name = branch.to_s
      name.start_with?("refs/") ? name : "refs/heads/#{name}"
    end

    def summarize(build)
      {
        id: build["id"],
        build_number: build["buildNumber"],
        # Azure's own answer about which repository the build ran against. The
        # webhook payload carries one too, and this is the one that is trusted:
        # gate routing must not follow an id the caller supplied.
        repository_id: build.dig("repository", "id"),
        # `status` is the lifecycle (notStarted/inProgress/completed) and
        # `result` is the verdict. A completed build with no result is not a
        # pass — that is the pair a single "status" field would flatten away.
        status: build["status"],
        result: build["result"],
        definition: build.dig("definition", "name"),
        branch: build["sourceBranch"].to_s.delete_prefix("refs/heads/"),
        commit: build["sourceVersion"],
        queued_at: build["queueTime"],
        finished_at: build["finishTime"],
        url: build.dig("_links", "web", "href")
      }.compact
    end
  end
end
