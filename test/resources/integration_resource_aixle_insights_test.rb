# frozen_string_literal: true

require "test_helper"

class IntegrationResourceAixleInsightsTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
  end

  test "insights_connected is true for an active Aixle Insights row" do
    integration = create(:integration, :aixle_insights, :active, company: @company, connected_by: @user,
                                       project_id: nil)

    assert IntegrationResource.new(integration).to_h.fetch("insightsConnected")
  end

  test "insights_connected is false for a non-active Aixle Insights row and for other providers" do
    inactive = create(:integration, :aixle_insights, company: @company, connected_by: @user, project_id: nil,
                                     status: :inactive)
    github = create(:integration, :github, company: @company, connected_by: @user)

    refute IntegrationResource.new(inactive).to_h.fetch("insightsConnected")
    refute IntegrationResource.new(github).to_h.fetch("insightsConnected")
  end

  test "the serialized hash never contains the ingest token or credentials" do
    integration = create(:integration, :aixle_insights, :active, company: @company, connected_by: @user,
                                       project_id: nil)
    integration.credentials_data = { "ingest_token" => "aixle_otel_SECRET_TOKEN_XYZ" }
    integration.save!

    json = IntegrationResource.new(integration).to_h.to_json

    refute_includes json, "aixle_otel_SECRET_TOKEN_XYZ"
    refute_includes json, "ingest_token"
    refute_includes json, "ingestToken"
    refute_includes json, "credentials"
  end
end
