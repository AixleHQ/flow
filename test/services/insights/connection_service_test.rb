# frozen_string_literal: true

require "test_helper"

module Insights
  class ConnectionServiceTest < ActiveSupport::TestCase
    setup do
      Settings.stubs(:insights).returns(OpenStruct.new(url: "https://insights.example.com", deployment_id: "dep-1",
                                                       deployment_secret: "dep-secret"))
      @company = create(:company)
      @admin = create(:user, :admin, company: @company)
      @client = FakeInsightsClient.new
      @service = ConnectionService.new(client: @client)
    end

    test "a code becomes the company's connection, its secret kept encrypted" do
      integration = @service.connect(company: @company, user: @admin, code: "ABCD-2345")

      assert_equal [ "insights", "active", nil, @admin.id ],
                   [ integration.provider, integration.status, integration.project_id, integration.connected_by_id ]
      assert_equal "Aixle Insights — Acme", integration.name
      assert_equal "aixle_flow_secret_1", integration.credentials_data["secret"]
      assert_not_includes integration.read_attribute(:credentials).to_s, "aixle_flow_secret_1"
      claim = @client.calls.assoc(:claim).last
      assert_equal [ "dep-1", "dep-secret", @company.id ], claim.values_at(:deployment_id, :deployment_secret, :company_id)
    end

    test "a new code for the same organization replaces the secret, not the connection" do
      first = @service.connect(company: @company, user: @admin, code: "A")
      second = @service.connect(company: @company, user: @admin, code: "B")

      assert_equal first.id, second.id
      assert_equal "aixle_flow_secret_2", second.reload.credentials_data["secret"]
    end

    test "a code for another organization is refused, and the connection it made revoked" do
      @service.connect(company: @company, user: @admin, code: "A")
      @client.organization_id = "org-2"

      error = assert_raises(ConnectionService::Error) { @service.connect(company: @company, user: @admin, code: "B") }

      assert_match(/already connected to Acme/, error.message)
      assert_equal [ :disconnect, { secret: "aixle_flow_secret_2" } ], @client.calls.last
      assert_equal 1, Integration.where(provider: "insights").count
    end

    test "a refused code reads as one, without saying why" do
      @client.fail_next(:claim, Client::Error.new("invalid_code", status: 422, code: "invalid_code"))

      error = assert_raises(ConnectionService::Error) { @service.connect(company: @company, user: @admin, code: "A") }

      assert_match(/not valid/, error.message)
      assert_not Integration.exists?(provider: "insights")
    end

    test "nothing connects on a deployment Insights has not registered" do
      Settings.stubs(:insights).returns(OpenStruct.new(url: "https://insights.example.com"))

      assert_raises(ConnectionService::Error) { @service.connect(company: @company, user: @admin, code: "A") }
      assert_empty @client.calls
    end

    test "rotating keeps the connection and stores the new secret" do
      integration = @service.connect(company: @company, user: @admin, code: "A")

      @service.rotate!(integration)

      assert_equal [ :rotate, { secret: "aixle_flow_secret_1" } ], @client.calls.last
      assert_equal "aixle_flow_secret_2", integration.reload.credentials_data["secret"]
    end

    test "disconnecting forgets the secret only once Insights revoked it" do
      integration = @service.connect(company: @company, user: @admin, code: "A")
      @client.fail_next(:disconnect, Client::Error.new("Insights is unreachable: SocketError"))

      assert_raises(ConnectionService::Error) { @service.disconnect!(integration) }
      assert Integration.exists?(integration.id)

      @service.disconnect!(integration)
      assert_not Integration.exists?(integration.id)
    end
  end
end
