# frozen_string_literal: true

class Repository < ApplicationRecord
  # Hosts a public (integration-less) repository may be cloned from. The clone
  # runs with no credentials, so this list is not a permission boundary — it is
  # an SSRF/exfiltration boundary: `clone_url` reaches a shell inside the
  # session container, and without it any attacker-supplied host could be
  # dialled from there. Keep it to hosts PublicRepositoryService can verify.
  PUBLIC_HOSTS = {
    "github.com" => "github",
    "gitlab.com" => "gitlab"
  }.freeze

  # Providers a repository can be cloned from. Integrations also cover Linear,
  # Coder and Slack, none of which host git.
  CODE_HOST_PROVIDERS = %w[github gitlab azure_devops].freeze

  # Azure project and repository names may contain spaces and other characters
  # the owner/repo format below rejects, and Azure identity is a triple of GUIDs
  # rather than a path — so `full_name` is a DISPLAY value for these rows and
  # carries a provider discriminator. The colon is what keeps the two namespaces
  # apart: it is invalid under FULL_NAME_FORMAT, so no GitHub or GitLab row can
  # ever be mistaken for an Azure one. A slash-only prefix would have collided
  # with legitimate nested GitLab groups.
  AZURE_FULL_NAME_PREFIX = "azure_devops:"
  FULL_NAME_FORMAT = %r{\A[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)+\z}
  # Display names only. Control characters are excluded because this string is
  # rendered in agent context files and the browser; the path components used to
  # build URLs come from verified IDs, never from here.
  AZURE_FULL_NAME_FORMAT = %r{\A#{AZURE_FULL_NAME_PREFIX}[^/\x00-\x1f]+/[^/\x00-\x1f]+/[^/\x00-\x1f]+\z}

  belongs_to :scope, polymorphic: true
  # Public repositories have no integration: nothing is authenticated, so there
  # is no installation, token or membership to point at.
  belongs_to :integration, optional: true

  before_validation :set_clone_url, if: -> { clone_url.blank? && full_name.present? && integration.present? }
  before_validation :mark_public_source_as_public, if: :public_source?

  validates :full_name, presence: true
  validates :full_name,
            format: { with: FULL_NAME_FORMAT, message: "must be in owner/repo format (e.g. org/repo or group/subgroup/repo)" },
            unless: :azure_devops?
  validates :full_name,
            format: { with: AZURE_FULL_NAME_FORMAT, message: "must be azure_devops:<organization>/<project>/<repository>" },
            if: :azure_devops?
  validates :full_name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :source_branch, presence: true
  validates :clone_url, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }
  validate :integration_hosts_code, if: -> { integration.present? }
  validate :public_clone_url_is_anonymous, if: -> { public_source? && clone_url.present? && full_name.present? }
  validate :owner_matches_installation_account, if: -> { integration.present? && integration.github? }
  validate :azure_identity_is_complete, if: :azure_devops?

  scope :for_project, ->(project) { where(scope_type: "Project", scope_id: project.id) }
  scope :for_integration, ->(integration) { where(integration: integration) }
  scope :public_sources, -> { where(integration_id: nil) }

  scope :visible_for_project, ->(project) {
    where(scope_type: "Project", scope_id: project.id)
  }

  # Project ids connected to a repo by full_name. Repositories are Project-scoped,
  # so this maps a repo directly to the projects that registered it. Used to fan
  # an inbound CI webhook out to every project that owns the repo.
  def self.project_ids_for(repo_full_name)
    where(full_name: repo_full_name, scope_type: "Project").pluck(:scope_id).uniq
  end

  def picker_name
    full_name
  end

  def scope_indicator
    "project"
  end

  def repo_name
    full_name&.split("/")&.last
  end

  # Meaningless for an Azure row — it would read back "azure_devops:<org>" —
  # which is why the only caller (owner_matches_installation_account) is gated on
  # `integration.github?`. Kept unchanged so GitHub and GitLab behaviour is
  # byte-identical.
  def owner_name
    full_name&.split("/")&.first
  end

  def azure_devops?
    integration.present? && integration.provider.to_s == "azure_devops"
  end

  # Display halves of the Azure `full_name`. Never used to address the API —
  # that is external_organization_id / external_project_id / external_id.
  def azure_display_parts
    return {} unless azure_devops? && full_name.to_s.start_with?(AZURE_FULL_NAME_PREFIX)

    org, project, repo = full_name.delete_prefix(AZURE_FULL_NAME_PREFIX).split("/", 3)
    { organization: org, project: project, repository: repo }
  end

  # Attached without an integration: cloned anonymously, read-only, and invisible
  # to the App-installation webhooks that drive CI triggers.
  def public_source?
    integration_id.nil? && integration.nil?
  end

  # "github" / "gitlab" / nil. Integration-backed repositories take it from the
  # integration; public ones from the clone host, which is allowlisted.
  def provider
    return integration.provider.to_s if integration.present?

    PUBLIC_HOSTS[clone_host]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[full_name source_branch is_private scope_type created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[scope integration]
  end

  private

  def set_clone_url
    case integration.provider.to_s
    when "github" then self.clone_url = "https://github.com/#{full_name}.git"
    when "gitlab" then self.clone_url = "https://gitlab.com/#{full_name}.git"
    when "azure_devops" then self.clone_url = azure_clone_url
    end
  end

  # Credential-free HTTPS on dev.azure.com, each path component encoded on its
  # own so a project called "Customer Platform" does not produce a broken or
  # traversable URL. Built from the DISPLAY names because that is what the Azure
  # Git endpoint routes on; the GUIDs remain the identity used for REST calls.
  def azure_clone_url
    parts = azure_display_parts
    return nil if parts.values.any?(&:blank?)

    encoded = parts.values_at(:organization, :project, :repository).map { |p| ERB::Util.url_encode(p) }
    "#{AzureDevops::AppConfig.api_host}/#{encoded[0]}/#{encoded[1]}/_git/#{encoded[2]}"
  end

  def mark_public_source_as_public
    self.is_private = false
  end

  def clone_uri
    URI.parse(clone_url.to_s)
  rescue URI::InvalidURIError
    nil
  end

  def clone_host
    clone_uri&.host
  end

  def integration_hosts_code
    return if CODE_HOST_PROVIDERS.include?(integration.provider.to_s)

    errors.add(:integration, "must be a GitHub, GitLab or Azure DevOps integration")
  end

  # An Azure row is addressed by organization + project + repository GUID. A row
  # missing any of the three has no stable identity: a rename would orphan it and
  # a tool call would have nothing to route on. The values come from verified
  # provider responses (AzureDevops::RepositoryService), never from the request.
  def azure_identity_is_complete
    %i[external_organization_id external_project_id external_id].each do |attr|
      errors.add(attr, "is required for an Azure DevOps repository") if public_send(attr).blank?
    end

    return if integration.blank? || external_project_id.blank?
    return if integration.azure_project_id.blank?
    return if integration.azure_project_id == external_project_id

    errors.add(:external_project_id, "does not belong to the integration's selected Azure project")
  end

  # A public repository is cloned by running `git clone <clone_url>` in the
  # session container, so the url must be exactly the anonymous https url of
  # `full_name` on an allowlisted host — no userinfo (credentials), no port,
  # no query, nothing else that could redirect the clone somewhere else.
  def public_clone_url_is_anonymous
    uri = clone_uri
    expected_path = "/#{full_name}.git"

    valid = uri.is_a?(URI::HTTPS) &&
      PUBLIC_HOSTS.key?(uri.host) &&
      uri.userinfo.nil? &&
      uri.port == 443 &&
      uri.query.nil? &&
      uri.fragment.nil? &&
      uri.path == expected_path

    return if valid

    errors.add(:clone_url, "must be the public https url of #{full_name} on #{PUBLIC_HOSTS.keys.to_sentence}")
  end

  # A GitHub installation only ever covers repositories of the account it was
  # installed on, and the clone token is scoped by repo NAME (`repositories:`
  # takes names, not full names). Without this, attaching "other-org/app" to an
  # installation that owns "acme/app" mints a token for acme/app and then clones
  # a different repository with it.
  def owner_matches_installation_account
    account = integration.github_account_login
    return if account.blank? || owner_name.blank?
    return if owner_name.casecmp?(account)

    errors.add(:full_name, "must belong to the #{account} GitHub installation")
  end
end
