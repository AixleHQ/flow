# frozen_string_literal: true

# The accounts a person connected (GitHub and GitLab) and what agents may do with them
# in each project (docs/design/github-user-identity.md §4.2). The profile's
# "Connected accounts" page calls this; it takes named parameters, never the request.
module UserConnections
  # Provider name => the module that knows how to connect and disconnect it.
  PROVIDERS = {
    Github::UserConnection::PROVIDER => Github::UserConnection,
    Gitlab::UserConnection::PROVIDER => Gitlab::UserConnection
  }.freeze

  # What the profile page shows each provider as.
  LABELS = { "github" => "GitHub", "gitlab" => "GitLab" }.freeze

  class Error < StandardError; end

  # The provider is not one a person can connect.
  class UnknownProvider < Error; end

  # The project is not one of the person's projects in the company.
  class ProjectNotFound < Error; end

  module_function

  def available?(provider:)
    known!(provider)
    PROVIDERS.fetch(provider).configured?
  end

  # The person's connection at the provider, a revoked one included (the page
  # shows it as needing a reconnect), or nil.
  def connection(user:, provider:)
    known!(provider)
    case provider
    when Github::UserConnection::PROVIDER then OauthCredential.latest_github_connection_of(user)
    else OauthCredential.latest_gitlab_connection_of(user)
    end
  end

  # One row per project of the company the person can reach; a project without a
  # stored row is an unsaved record with both switches off.
  def consents(user:, company:, provider:)
    known!(provider)
    return [] unless company

    stored = ActAsConsent.where(user: user, provider: provider).index_by(&:project_id)
    Project.for_user_in_company(user, company).order(:name).map do |project|
      stored[project.id] || ActAsConsent.new(user: user, project: project, company: project.company, provider: provider)
    end
  end

  def disconnect!(user:, provider:)
    known!(provider)
    PROVIDERS.fetch(provider).disconnect!(user)
  end

  # Sets the switches that are given (true or false); a nil leaves its switch as it is.
  # Two overlapping first-time updates for one project end on the one row: the losing
  # insert hits the unique index (create_or_find_by! then finds the winner's row), or,
  # when the winner committed first, the uniqueness validation.
  def update_consent!(user:, company:, provider:, project_id:, in_own_tasks: nil, in_others_tasks: nil)
    known!(provider)
    project = company && Project.for_user_in_company(user, company).find_by(id: project_id)
    raise ProjectNotFound, "project #{project_id} is not one of the person's projects in the company" unless project

    consent = consent_row(user, project, provider)
    consent.in_own_tasks = in_own_tasks unless in_own_tasks.nil?
    consent.in_others_tasks = in_others_tasks unless in_others_tasks.nil?
    consent.save!
    consent
  end

  def known!(provider)
    raise UnknownProvider, "unknown provider #{provider.inspect}" unless PROVIDERS.key?(provider)
  end

  def consent_row(user, project, provider)
    attributes = { user: user, project: project, company: project.company, provider: provider }
    ActAsConsent.find_by(attributes) || ActAsConsent.create_or_find_by!(attributes)
  rescue ActiveRecord::RecordInvalid
    ActAsConsent.find_by(attributes) || raise
  end
end
