# frozen_string_literal: true

require "test_helper"
require "support/contracts/integration_provider_contracts"

class Youtrack::ConnectServiceContractTest < ActiveSupport::TestCase
  include IntegrationProviderContracts::ConnectService

  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    UrlSafetyValidator.stubs(:resolved_addresses).returns([ IPAddr.new("93.184.216.34") ])
    stub_request(:get, %r{https://youtrack.example.com/api/users/me})
      .to_return(status: 200, body: { id: "user-1", login: "bot" }.to_json)
    stub_request(:get, %r{https://youtrack.example.com/api/admin/projects/0-1})
      .to_return(status: 200, body: { id: "0-1", name: "App", shortName: "APP" }.to_json)
  end

  def connect_service = Youtrack::ConnectService.new(company: @company, connected_by: @user)
  def valid_connection_params
    { base_url: "https://youtrack.example.com", permanent_token: "perm:secret", youtrack_project_id: "0-1",
      webhook_header: "X-Custom-Token", webhook_token: "s" * 32 }
  end
end

class Youtrack::WebhookAdapterContractTest < ActiveSupport::TestCase
  include IntegrationProviderContracts::WebhookAdapter

  setup do
    @company = create(:company)
    @integration = create(:integration, :active, provider: :youtrack, company: @company,
      settings: { "youtrack_project_id" => "0-1" })
    @endpoint = create(:webhook_endpoint, company: @company, provider: :youtrack,
      config: { "integration_id" => @integration.id })
  end

  def adapter = Youtrack::WebhookAdapter.new
  attr_reader :integration, :endpoint
  def valid_payload
    { "event" => "issueCreated", "timestamp" => "2026-09-18T00:00:00Z",
      "issue" => { "id" => "2-1", "idReadable" => "APP-1", "summary" => "Hello",
        "project" => { "id" => "0-1" } } }
  end
end

class Youtrack::IntegrationResolvableContractTest < ActiveSupport::TestCase
  include IntegrationProviderContracts::IntegrationResolvable

  setup do
    company = create(:company)
    owner = create(:user, company: company)
    project = create(:project, company: company, owner: owner)
    create(:integration, :active, provider: :youtrack, company: company, project: nil)
    @preferred_integration = create(:integration, :active, provider: :youtrack, company: company, project: project)
    klass = Class.new do
      include InternalTools::Concerns::IntegrationResolvable
      resolves_integration_for :youtrack
      attr_accessor :project, :workflow_run
    end
    @resolver = klass.new
    @resolver.project = project
  end

  attr_reader :resolver, :preferred_integration
end
