# frozen_string_literal: true

require "test_helper"

class Web::Company::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(@user)
  end

  test "index renders integrations page" do
    create(:integration, company: @company, connected_by: @user)

    get company_integrations_path
    assert_inertia_page "Company/Integrations/Index"
  end

  test "create gitlab integration redirects" do
    Gitlab::IntegrationService.any_instance.stubs(:create).returns(
      create(:integration, :gitlab, :active, company: @company, connected_by: @user)
    )

    post company_integrations_path, params: { provider: "gitlab", personal_access_token: "glpat-test" }
    assert_response :redirect
  end

  test "create with unsupported provider redirects with alert" do
    post company_integrations_path, params: { provider: "unsupported" }
    assert_response :redirect
  end

  test "create coder integration happy path" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
      status: 200,
      body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_difference("Integration.count", 1) do
      post company_integrations_path, params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "tok-1",
        lockTtlMinutes: "60"
      }
    end

    integration = Integration.last
    assert_equal "coder", integration.provider.to_s
    assert_equal "active", integration.status.to_s
    assert_response :redirect
  end

  test "create coder integration missing lock_ttl_minutes persists record in error state" do
    assert_difference("Integration.count", 1) do
      post company_integrations_path, params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "tok-1"
      }
    end

    integration = Integration.last
    assert_equal "error", integration.status.to_s
    assert_match(/Lock TTL minutes is required/, integration.settings["error"])
    assert_response :redirect
  end

  test "create coder integration sad path persists record in error state" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(status: 401)

    assert_difference("Integration.count", 1) do
      post company_integrations_path, params: {
        provider: "coder",
        coderUrl: "https://coder.example.com",
        sessionToken: "bad-token",
        lockTtlMinutes: "60"
      }
    end

    integration = Integration.last
    assert_equal "coder", integration.provider.to_s
    assert_equal "error", integration.status.to_s
    assert_match(/HTTP 401/, integration.settings["error"])
    assert_response :redirect
  end

  test "create coder integration with optional advanced fields persists them" do
    stub_request(:get, "https://coder.example.com/api/v2/users/me").to_return(
      status: 200,
      body: { id: "user-uuid", username: "alice", email: "alice@example.com" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    post company_integrations_path, params: {
      provider: "coder",
      coderUrl: "https://coder.example.com",
      sessionToken: "tok-1",
      defaultTemplate: "aws-ec2-spot-v3",
      machinePrefix: "aixle-test",
      lockTtlMinutes: "90"
    }

    integration = Integration.last
    assert_equal "aws-ec2-spot-v3", integration.settings["default_template"]
    assert_equal "aixle-test", integration.settings["machine_prefix"]
    assert_equal 90, integration.settings["lock_ttl_minutes"]
  end

  test "destroy works for a coder integration" do
    integration = create(:integration, :coder, :active, company: @company, connected_by: @user)

    assert_difference("Integration.count", -1) do
      delete company_integration_path(integration)
    end
    assert_response :redirect
  end

  test "destroy removes integration" do
    integration = create(:integration, company: @company, connected_by: @user)

    delete company_integration_path(integration)
    assert_response :redirect
  end
end
