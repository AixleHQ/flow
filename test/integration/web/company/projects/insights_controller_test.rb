# frozen_string_literal: true

require "test_helper"

# Web::Company::Projects::InsightsController and its policy: the connection is a company
# admin's, a project's switches its owner's or a company admin's.
class Web::Company::Projects::InsightsControllerTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    Settings.stubs(:insights).returns(OpenStruct.new(url: "https://insights.example.com", deployment_id: "dep-1",
                                                     deployment_secret: "dep-secret"))
    @insights = FakeInsightsClient.new
    Insights::Client.stubs(:build).returns(@insights)
  end

  teardown { teardown_authz }

  test "connecting is a company admin's" do
    expectations = { admin: :allowed_write, owner: :denied, collaborator: :denied, viewer: :denied,
                     stranger: :not_found, foreign_admin: :not_found }
    assert_role_matrix(expectations, transport: :web) do
      post connect_company_project_insights_path(@project), params: { code: "ABCD-2345" }
    end
    assert Integration.exists?(company: @company, provider: "insights", status: "active")
  end

  test "a project's switches are its owner's or a company admin's" do
    expectations = { owner: :allowed_write, admin: :allowed_write, collaborator: :denied, viewer: :denied,
                     stranger: :not_found, foreign_admin: :not_found }
    assert_role_matrix(expectations, transport: :web) do
      patch company_project_insights_path(@project), params: { export: true }
    end
  end

  test "prompt sharing is saved only on an exported project, and turning export off turns it off" do
    sign_in_as(@admin)

    patch company_project_insights_path(@project), params: { export: false, share_prompts: true }
    assert_equal({ "export" => false, "share_prompts" => false, "project_id" => nil }, @project.reload.insights_settings)

    patch company_project_insights_path(@project), params: { export: true, share_prompts: true, insights_project_id: "ip-1" }
    assert_equal({ "export" => true, "share_prompts" => true, "project_id" => "ip-1" }, @project.reload.insights_settings)

    patch company_project_insights_path(@project), params: { export: false }
    assert_equal false, @project.reload.insights_settings["share_prompts"] # rubocop:disable Minitest/RefuteFalse
  end

  test "a refused code comes back against the field" do
    sign_in_as(@admin)
    @insights.fail_next(:claim, Insights::Client::Error.new("invalid_code", status: 422, code: "invalid_code"))

    post connect_company_project_insights_path(@project), params: { code: "WRONG" }

    assert_redirected_to company_project_integrations_path(@project)
    assert_match(/not valid/, Array(session["inertia_errors"][:code]).to_sentence)
  end

  test "projects lists the organization's projects for the mapping" do
    connect_to_insights!(@project)
    sign_in_as(@owner)

    get projects_company_project_insights_path(@project)

    assert_response :success
    assert_equal [ { "id" => "ip-1", "name" => "Platform" } ], response.parsed_body["projects"]
  end

  test "the integrations page shows the connection and the switches, never the secret" do
    integration = connect_to_insights!(@project, share_prompts: false)
    sign_in_as(@admin)

    get company_project_integrations_path(@project)

    assert_inertia_props do |props|
      insights = props[:insights]
      insights["enabled"] && insights.dig("connection", "organizationName") == "Acme" &&
        insights["project"] == { "export" => true, "sharePrompts" => false, "insightsProjectId" => nil } &&
        insights["canConnect"] && props[:integrations].none? { |i| i["provider"] == "insights" }
    end
    assert_not_includes response.body, integration.credentials_data["secret"]
  end
end
