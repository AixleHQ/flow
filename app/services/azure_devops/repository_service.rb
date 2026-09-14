# frozen_string_literal: true

module AzureDevops
  # Repository discovery and verified attachment, in the shape RepositoryService
  # dispatches to (`list_available`, `find_repo`, `list_branches`, `configure`,
  # `remove`) so the existing picker path works unchanged.
  #
  # The difference from the GitHub and GitLab adapters is identity: those route
  # on `full_name`, while an Azure repository is a GUID inside a project GUID
  # inside an organization. Names here are display values that a rename can
  # change underneath us; the GUIDs are what every later call uses.
  class RepositoryService
    def initialize(integration)
      @integration = integration
    end

    attr_reader :integration

    # Every repository in every project this connection covers. One project that
    # cannot be read does not hide the others: a connection can outlive a project
    # being archived or its access being narrowed, and answering with nothing
    # would look like an empty organization.
    def list_available
      integration.azure_project_ids.flat_map { |project_id| repositories_in(project_id) }
    end

    # `identifier` is an Azure repository GUID. Deliberately not a name: a name
    # lookup would let a caller reach a repository in another project that
    # happens to share it.
    # `project_id` is optional because the caller does not always know it — a
    # GUID pasted into the repository form carries no project. It is searched
    # for in the connection's projects rather than assumed, and the result is
    # still checked against the project it was found in, so a GUID from a
    # project this connection does not cover finds nothing.
    def find_repo(identifier, project_id: nil)
      candidates = project_id.present? ? [ project_id.to_s ] : integration.azure_project_ids

      candidates.each do |candidate|
        repo = fetch_repo(identifier, candidate)
        return repo if repo
      end
      nil
    end

    def list_branches(identifier, project_id: nil)
      project_id ||= find_repo(identifier)&.dig(:external_project_id)
      return [] if project_id.blank?

      client, resolved = client_for(:"repositories.read", project_id: project_id)
      refs, = client.paginate("_apis", "git", "repositories", identifier.to_s, "refs",
                              family: :git, project: resolved.project_id,
                              params: { filter: "heads/", "$top" => 200 }, limit: 500)

      # `refs/heads/` is stripped for display only — the qualified form is what
      # pull request creation requires, and it is rebuilt there rather than
      # round-tripped through the UI.
      refs.filter_map { |ref| ref["name"].to_s.delete_prefix("refs/heads/").presence }.sort
    rescue Error => e
      Rails.logger.warn("[AzureDevops::RepositoryService] branches for #{identifier} failed: #{e.code}")
      []
    end

    # Azure DevOps uses organization/project Service Hooks rather than
    # per-repository webhooks, so there is nothing to install or remove here.
    # The parity extension adds subscriptions at the connection level.
    def configure(_repository); end
    def remove(_repository); end

    # Build an attachable Repository from VERIFIED provider data. Everything
    # that ends up on the row — ids, names, clone url, privacy — comes from
    # Azure's answer; the request supplies only which repository to look up.
    def build_repository(external_id:, scope:, source_branch: nil, purpose: nil)
      details = find_repo(external_id)
      raise NotFound, "That repository is not visible through this connection" if details.nil?

      branch = source_branch.presence || details[:default_branch]
      if branch.blank?
        # An empty Azure repository has no defaultBranch. Inventing "main" here
        # produces a clone that fails inside the container with nothing to
        # explain it.
        raise ValidationFailed, "#{details[:name]} is empty — push an initial commit before attaching it"
      end

      Repository.new(
        scope: scope,
        integration: integration,
        full_name: details[:full_name],
        clone_url: details[:clone_url],
        source_branch: branch,
        is_private: details[:is_private],
        description: details[:description],
        purpose: purpose,
        external_id: details[:external_id],
        external_project_id: details[:external_project_id],
        external_organization_id: details[:external_organization_id]
      )
    end

    private

    def repositories_in(project_id)
      client, resolved = client_for(:"repositories.read", project_id: project_id)
      payload = client.get("_apis", "git", "repositories", family: :git, project: resolved.project_id)

      Array(payload["value"]).map { |repo| summarize(repo, resolved) }
    rescue Error => e
      Rails.logger.warn("[AzureDevops::RepositoryService] listing project #{project_id} for " \
                        "integration #{integration.id} failed: #{e.code}")
      []
    end

    def fetch_repo(identifier, project_id)
      client, resolved = client_for(:"repositories.read", project_id: project_id)
      repo = client.get("_apis", "git", "repositories", identifier.to_s, family: :git, project: resolved.project_id)

      verify_scope!(repo, resolved)
      summarize(repo, resolved)
    rescue Error => e
      Rails.logger.debug { "[AzureDevops::RepositoryService] #{identifier} not in #{project_id}: #{e.code}" }
      nil
    end

    def client_for(capability, project_id: nil)
      CredentialProvider.client_for(integration, capability: capability, project_id: project_id)
    end

    # A repository Azure returns must belong to the project this connection
    # selected. Without this an id from another project in the same
    # organization would attach happily and then be reachable by every tool.
    def verify_scope!(repo, resolved)
      project_id = repo.dig("project", "id")
      return if project_id.present? && project_id == resolved.project_id

      raise NotAuthorized, "That repository is not in this connection's Azure project"
    end

    def summarize(repo, resolved)
      organization = resolved.organization
      project_name = repo.dig("project", "name").to_s
      name = repo["name"].to_s

      {
        external_id: repo["id"],
        external_project_id: repo.dig("project", "id") || resolved.project_id,
        external_organization_id: resolved.installation&.organization_id.presence || organization,
        name: name,
        project_name: project_name,
        # Display identity. The colon discriminator keeps it out of the
        # owner/repo namespace the other providers validate against.
        full_name: "#{Repository::AZURE_FULL_NAME_PREFIX}#{organization}/#{project_name}/#{name}",
        default_branch: repo["defaultBranch"].to_s.delete_prefix("refs/heads/").presence,
        clone_url: normalized_clone_url(repo, organization, project_name, name),
        is_private: repo.dig("project", "visibility").to_s != "public",
        description: nil,
        size: repo["size"]
      }
    end

    # Azure returns `remoteUrl` (and sometimes `webUrl`), and those are still
    # provider-supplied strings that reach a `git clone` command line. Rather
    # than validating an arbitrary URL, the canonical form is rebuilt from the
    # verified names and the provider's version is only accepted when it matches
    # host and shape.
    def normalized_clone_url(repo, organization, project_name, name)
      canonical = "#{AppConfig.api_host}/#{ERB::Util.url_encode(organization)}/" \
                  "#{ERB::Util.url_encode(project_name)}/_git/#{ERB::Util.url_encode(name)}"

      remote = repo["remoteUrl"].to_s
      return canonical if remote.blank?

      uri = begin
        URI.parse(remote)
      rescue URI::InvalidURIError
        nil
      end

      # Anything with credentials in it, a query, a fragment or a different host
      # is discarded rather than repaired.
      return canonical unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      return canonical unless uri.host == URI.parse(AppConfig.api_host).host

      remote
    end
  end
end
