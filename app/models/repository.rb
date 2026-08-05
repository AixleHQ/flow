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
  CODE_HOST_PROVIDERS = %w[github gitlab].freeze

  belongs_to :scope, polymorphic: true
  # Public repositories have no integration: nothing is authenticated, so there
  # is no installation, token or membership to point at.
  belongs_to :integration, optional: true

  before_validation :set_clone_url, if: -> { clone_url.blank? && full_name.present? && integration.present? }
  before_validation :mark_public_source_as_public, if: :public_source?

  validates :full_name, presence: true,
                        format: { with: %r{\A[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)+\z}, message: "must be in owner/repo format (e.g. org/repo or group/subgroup/repo)" }
  validates :full_name, uniqueness: { scope: %i[scope_type scope_id], message: "already exists in this scope" }
  validates :source_branch, presence: true
  validates :clone_url, presence: true
  validates :scope_type, presence: true, inclusion: { in: %w[Project] }
  validate :integration_hosts_code, if: -> { integration.present? }
  validate :public_clone_url_is_anonymous, if: -> { public_source? && clone_url.present? && full_name.present? }
  validate :owner_matches_installation_account, if: -> { integration.present? && integration.github? }

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

  def owner_name
    full_name&.split("/")&.first
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
    base = case integration.provider.to_s
    when "github" then "https://github.com"
    when "gitlab" then "https://gitlab.com"
    end
    self.clone_url = "#{base}/#{full_name}.git" if base
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

    errors.add(:integration, "must be a GitHub or GitLab integration")
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
