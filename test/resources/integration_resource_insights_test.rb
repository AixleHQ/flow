# frozen_string_literal: true

require "test_helper"

class IntegrationResourceInsightsTest < ActiveSupport::TestCase
  test "the serialized project integration never contains the ingest token or credentials" do
    company = create(:company)
    user = create(:user, :employee, company: company)
    project = create(:project, company: company, owner: user)
    integration = create(:integration, :insights, :active, company: company, project: project, connected_by: user)
    integration.credentials_data = { "ingest_token" => "aixle_otel_SECRET_TOKEN_XYZ" }
    integration.save!

    resource = IntegrationResource.new(integration).to_h
    json = resource.to_json

    assert_equal "insights", resource.fetch("provider")
    assert_equal project.id, resource.fetch("projectId")
    assert_equal "project", resource.fetch("scopeIndicator")
    refute_includes json, "aixle_otel_SECRET_TOKEN_XYZ"
    refute_includes json, "ingest_token"
    refute_includes json, "ingestToken"
    refute_includes json, "credentials"
  end
end
