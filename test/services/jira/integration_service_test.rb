# frozen_string_literal: true

require "test_helper"

class Jira::IntegrationServiceTest < ActiveSupport::TestCase
  setup do
    with_jira_oauth_app
    @jira = stub_jira!
    company = create(:company)
    @user = create(:user, company: company)
    @project = create(:project, company: company, owner: @user)
    @service = Jira::IntegrationService.new(company: @project.company, connected_by: @user, project: @project)
  end

  def stub_service_account_login
    stub_request(:get, "https://acme.atlassian.net/_edge/tenant_info").to_return(status: 200, body: { cloudId: "cloud-acme" }.to_json)
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").with(body: hash_including("grant_type" => "client_credentials"))
      .to_return(status: 200, body: { access_token: "sa-at", expires_in: 3600 }.to_json)
  end

  def stub_oauth_grant(sites)
    stub_request(:post, "#{JIRA_AUTH}/oauth/token").with(body: hash_including("grant_type" => "authorization_code"))
      .to_return(status: 200, body: { access_token: "at-1", refresh_token: "rt-1", expires_in: 3600 }.to_json)
    stub_request(:get, "#{JIRA_API}/oauth/token/accessible-resources")
      .to_return(status: 200, body: sites.map { |id, name| { id: id, name: name, url: "https://#{name}.atlassian.net", scopes: [ "read:jira-work" ] } }.to_json)
  end

  test "a service account connects to the projects picked, each becoming a tracker, and gets its admin webhook" do
    stub_service_account_login

    integration = @service.connect_service_account(site_url: "acme.atlassian.net", client_id: "sa-client",
                                                   client_secret: "sa-secret", project_ids: [ "10000" ])

    assert_equal [ "active", "Jira · acme.atlassian.net" ], [ integration.status, integration.name ]
    assert_equal({ "auth_mode" => "service_account", "cloud_id" => "cloud-acme", "site_url" => "https://acme.atlassian.net",
                   "dedicated_identity" => true, "jira_projects" => [ { "id" => "10000", "key" => "ENG", "name" => "Engineering" } ] },
                 integration.settings.slice("auth_mode", "cloud_id", "site_url", "dedicated_identity", "jira_projects"))
    assert_equal [ "sa-client", "sa-secret", "sa-at" ], integration.credentials_data.values_at("client_id", "client_secret", "access_token")
    tracker = integration.project_trackers.sole
    assert_equal [ "10000", "ENG", "engineering", true ], [ tracker.external_scope_id, tracker.external_scope_key, tracker.handle, tracker.primary ]
    assert_equal "manual", integration.tracker_subscriptions.sole.strategy
  end

  test "reconnecting a site the project already has renews that connection in place" do
    stub_service_account_login
    first = @service.connect_service_account(site_url: "acme.atlassian.net", client_id: "a", client_secret: "b", project_ids: [ "10000" ])

    second = @service.connect_service_account(site_url: "https://acme.atlassian.net", client_id: "c", client_secret: "d",
                                              project_ids: %w[10000 10001])

    assert_equal first, second
    assert_equal 2, second.project_trackers.count
    assert_equal "c", second.credentials_data["client_id"]
  end

  test "a project the credential cannot see is refused" do
    stub_service_account_login

    assert_raises(Jira::IntegrationService::ConfigurationError) do
      @service.connect_service_account(site_url: "acme.atlassian.net", client_id: "a", client_secret: "b", project_ids: [ "99999" ])
    end
    assert_equal 0, Integration.where(project: @project).count
  end

  test "an OAuth grant for several sites waits for the site and projects, then finishes" do
    stub_oauth_grant([ %w[cloud-acme acme], %w[cloud-beta beta] ])

    pending = @service.connect_oauth(code: "code-1")

    assert_equal [ "inactive", "Jira" ], [ pending.status, pending.name ]
    assert_equal %w[cloud-acme cloud-beta], pending.settings["sites"].pluck("id")
    assert_empty pending.project_trackers

    done = @service.configure(pending, cloud_id: "cloud-beta", project_ids: [ "10001" ])

    assert_equal [ "active", "cloud-beta", "Jira · beta.atlassian.net", false ],
                 [ done.status, done.settings["cloud_id"], done.name, done.settings["dedicated_identity"] ]
    assert_equal [ "10001" ], done.project_trackers.pluck(:external_scope_id)
  end

  test "an OAuth grant for the one site the project is connected to renews that connection" do
    existing = create(:integration, :jira_oauth, :active, project: @project, company: @project.company)
    stub_oauth_grant([ %w[cloud-acme acme] ])

    renewed = @service.connect_oauth(code: "code-2")

    assert_equal [ existing, "active" ], [ renewed, renewed.status ]
    assert_equal [ "at-1", "rt-1" ], renewed.reload.credentials_data.values_at("access_token", "refresh_token")
  end

  test "dropping a project detaches its tracker; a 3LO connection with a tracker trigger registers its webhook" do
    integration = create(:integration, :jira_oauth, :active, project: @project, company: @project.company)
    Trackers::Provisioning.ensure_for!(integration)
    create(:trigger_binding, project: @project, workflow: create(:workflow, scope: @project), created_by: @user,
                             event_type: "tracker.issue.created")

    @service.configure(integration, project_ids: [ "10000" ], dedicated_identity: "true")

    assert_equal({ "10000" => "active", "10001" => "detached" }, integration.project_trackers.pluck(:external_scope_id, :status).to_h)
    assert_equal "project IN (10000)", @jira.calls_to(:register_webhook).last[:jql]
    assert integration.reload.settings["dedicated_identity"]
  end

  test "a connection test refreshes what it sees and flags a refused credential" do
    integration = create(:integration, :jira, :active, project: @project, company: @project.company)

    assert_equal({ status: :active, missing: [] }, @service.test(integration))

    @jira.fail_next(:myself, Jira::Error.new("Jira rejected this connection's credential", code: "not_authorized"))
    result = @service.test(integration)
    assert_equal [ :error, "not_authorized" ], result.values_at(:status, :error)
    assert_equal [ "error", "not_authorized" ], [ integration.reload.status, integration.settings["error"] ]
  end
end
