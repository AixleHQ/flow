# frozen_string_literal: true

require "test_helper"

# Both ways of connecting Linear through the real endpoints: an API key pasted
# into the dialog, and Aixle's Linear OAuth app via its callback. Linear's token
# endpoint is WebMock-stubbed (Linear::Oauth stays real); the GraphQL API behind
# it is FakeLinear::Api.
class Web::Company::Projects::LinearIntegrationsTest < ActionDispatch::IntegrationTest
  ENG = FakeLinear::Api::ENG

  setup do
    with_linear_oauth_app
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @linear = stub_linear!
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    @project = create(:project, company: @company, owner: @user)
    sign_in_as(@user)
  end

  test "the page says whether the OAuth app is available" do
    get company_project_integrations_path(@project)

    assert_inertia_props { |props| assert props["linear"]["oauthEnabled"] }
  end

  test "an API key is checked, then connected to the teams picked" do
    post linear_inspect_company_project_integrations_path(@project), params: { api_key: "lin_api_x" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal [ "Aixle Bot", "Acme", %w[ENG OPS] ], [ body.dig("identity", "name"), body.dig("organization", "name"), body["teams"].pluck("key") ]

    post company_project_integrations_path(@project), params: { provider: "linear", api_key: "lin_api_x", team_ids: [ ENG ], dedicated_identity: "true" }

    assert_redirected_to company_project_integrations_path(@project)
    integration = Integration.find_by!(project: @project, provider: "linear")
    assert_equal [ "active", [ ENG ], true ],
                 [ integration.status.to_s, integration.project_trackers.pluck(:external_scope_id), integration.settings["dedicated_identity"] ]
  end

  test "a key Linear refuses is reported against the dialog, and nothing is saved" do
    @linear.fail_next(:identity, Trackers::Error.new("Authentication required", code: "not_authorized"))

    post linear_inspect_company_project_integrations_path(@project), params: { api_key: "bad" }, as: :json

    assert_response :unprocessable_content
    assert_equal "not_authorized", response.parsed_body["error"]
    assert_equal 0, Integration.where(project: @project).count
  end

  test "the OAuth app round trip leaves a pending connection that the team picker finishes" do
    get linear_oauth_start_company_project_integrations_path(@project)
    authorize = URI.parse(response.location)
    assert_equal [ "linear.app", "app" ], [ authorize.host, Rack::Utils.parse_query(authorize.query)["actor"] ]
    state = Rack::Utils.parse_query(authorize.query)["state"]
    stub_request(:post, "https://api.linear.app/oauth/token")
      .to_return(status: 200, body: { access_token: "at", refresh_token: "rt", expires_in: 86_399 }.to_json)

    get linear_oauth_callback_path, params: { code: "c", state: state }

    assert_nil flash[:alert]
    integration = Integration.find_by!(project: @project, provider: "linear")
    assert_redirected_to company_project_integrations_path(@project, linear_setup: integration.id)
    assert_equal "inactive", integration.status.to_s

    get linear_teams_company_project_integration_path(@project, integration), as: :json
    assert_equal %w[ENG OPS], response.parsed_body["teams"].pluck("key")

    patch company_project_integration_path(@project, integration), params: { team_ids: [ ENG ] }
    assert_equal [ "active", [ ENG ] ], [ integration.reload.status.to_s, integration.project_trackers.pluck(:external_scope_id) ]

    get linear_oauth_callback_path, params: { code: "c", state: state }
    assert_equal "This Linear authorization link was already used", flash[:alert]
  end

  test "a callback whose state another user started is refused" do
    other = create(:user, :admin, company: @company)
    state = Oauth::State.encode(owner_type: "Project", owner_id: @project.id, user_id: other.id, return_to: nil,
                                code_verifier: nil, provider: "linear")

    get linear_oauth_callback_path, params: { code: "c", state: state }

    assert_redirected_to root_path
    assert_equal "Invalid or expired Linear authorization", flash[:alert]
  end

  test "testing a Linear connection re-reads it" do
    integration = create(:integration, :linear, :active, project: @project, company: @company)

    post test_connection_company_project_integration_path(@project, integration)

    assert_equal "Connection verified", flash[:notice]
    assert @linear.called?(:identity)
  end
end
