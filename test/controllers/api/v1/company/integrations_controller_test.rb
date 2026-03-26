# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::IntegrationsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_admin = create(:user, :admin, company: @other_company)

    @integration = create(:integration, :github, :active,
      company: @company, connected_by: @admin, name: "acme-corp")
  end

  # ====== GITHUB_SETUP ======

  test "#github_setup redirects when installation_id blank" do
    sign_in @admin

    get :github_setup, params: { installation_id: "" }, format: :html

    assert_redirected_to "/company/integrations"
  end

  test "#github_setup redirects to project tab when state is project and installation_id blank" do
    sign_in @admin
    project = create(:project, company: @company, owner: @admin)

    get :github_setup, params: { installation_id: "", state: "project:#{project.id}" }, format: :html

    assert_redirected_to "/company/projects/#{project.id}/integrations"
  end

  test "#github_setup creates project-scoped integration when state references project" do
    sign_in @admin
    project = create(:project, company: @company, owner: @admin)
    initial_count = Integration.count

    mock_service = mock("token_service")
    mock_service.expects(:verify_installation).returns({
      id: 12_345,
      account_login: "proj-org",
      account_type: "Organization",
      target_type: "Organization",
      permissions: {}
    })
    Github::TokenService.expects(:new).returns(mock_service)

    get :github_setup, params: { installation_id: "12345", state: "project:#{project.id}" }, format: :html

    assert_redirected_to "/company/projects/#{project.id}/integrations"
    assert_equal initial_count + 1, Integration.count
    integration = @company.integrations.find { |i| i.installation_id == "12345" }
    assert integration.present?
    assert_equal project.id, integration.project_id
    assert_equal "proj-org", integration.name
  end

  test "#github_setup creates integration when verification succeeds" do
    sign_in @admin
    initial_count = Integration.count

    mock_service = mock("token_service")
    mock_service.expects(:verify_installation).returns({
      id: 88_888,
      account_login: "setup-org",
      account_type: "Organization",
      target_type: "Organization",
      permissions: {}
    })
    Github::TokenService.expects(:new).returns(mock_service)

    get :github_setup, params: { installation_id: "88888" }, format: :html

    assert_redirected_to "/company/integrations"
    assert_equal initial_count + 1, Integration.count
    integration = @company.integrations.find { |i| i.installation_id == "88888" }
    assert integration.present?
    assert_equal "setup-org", integration.name
    assert_equal "active", integration.status
  end

  test "#github_setup sets error status when verification fails" do
    sign_in @admin
    initial_count = Integration.count

    Github::TokenService.expects(:new).raises(
      Github::TokenService::AuthenticationError.new("Invalid token")
    )

    get :github_setup, params: { installation_id: "77777" }, format: :html

    assert_redirected_to "/company/integrations"
    assert_equal initial_count + 1, Integration.count
    integration = @company.integrations.find { |i| i.installation_id == "77777" }
    assert integration.present?
    assert_equal "error", integration.status
    assert integration.settings["error"].present?
  end

  # ====== INDEX ======

  test "#index returns company integrations for admin" do
    sign_in @admin

    get :index

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["name"] == "acme-corp" }
    assert { json["items"].first["provider"] == "github" }
    assert { json["items"].first["status"] == "active" }
    assert { json["items"].first["connected_by"].present? }
  end

  test "#index does not include credentials" do
    sign_in @admin

    get :index

    json = response.parsed_body
    item = json["items"].first
    assert { item["credentials"].nil? }
  end

  test "#index does not return other company integrations" do
    create(:integration, :github, company: @other_company, connected_by: @other_admin, name: "other-org")
    sign_in @admin

    get :index

    json = response.parsed_body
    names = json["items"].map { |i| i["name"] }
    assert { names == [ "acme-corp" ] }
  end

  test "#index requires admin role" do
    sign_in @employee
    get :index
    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index
    assert_response :unauthorized
  end

  # ====== SHOW ======

  test "#show returns integration for admin" do
    sign_in @admin

    get :show, params: { id: @integration.id }

    assert_response :success
    json = response.parsed_body
    assert { json["data"]["name"] == "acme-corp" }
    assert { json["data"]["connected_by"].present? }
  end

  # ====== CREATE ======

  test "#create creates github integration with verified installation" do
    sign_in @admin

    mock_service = mock("token_service")
    mock_service.expects(:verify_installation).returns({
      id: 99_999,
      account_login: "new-org",
      account_type: "Organization",
      target_type: "Organization",
      permissions: { contents: "read" }
    })
    Github::TokenService.expects(:new).returns(mock_service)

    assert_difference("Integration.count", 1) do
      post :create, params: { provider: "github", installation_id: "99999" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "new-org" }
    assert { json["data"]["status"] == "active" }
  end

  test "#create sets error status when verification fails" do
    sign_in @admin

    Github::TokenService.expects(:new).raises(
      Github::TokenService::AuthenticationError.new("Bad credentials")
    )

    assert_difference("Integration.count", 1) do
      post :create, params: { provider: "github", installation_id: "bad-id" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["status"] == "error" }
  end

  test "#create creates gitlab integration with valid PAT" do
    sign_in @admin

    mock_service = mock("token_service")
    mock_service.expects(:verify_token).returns({ username: "gitlab-user" })
    Gitlab::TokenService.expects(:new).returns(mock_service)

    assert_difference("Integration.count", 1) do
      post :create, params: { provider: "gitlab", personal_access_token: "glpat-valid" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "gitlab-user" }
    assert { json["data"]["status"] == "active" }
    assert { json["data"]["provider"] == "gitlab" }
  end

  test "#create sets error status when gitlab PAT is invalid" do
    sign_in @admin

    Gitlab::TokenService.expects(:new).raises(
      Gitlab::TokenService::AuthenticationError.new("Invalid PAT")
    )

    assert_difference("Integration.count", 1) do
      post :create, params: { provider: "gitlab", personal_access_token: "glpat-bad" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["status"] == "error" }
    assert { json["data"]["provider"] == "gitlab" }
  end

  test "#create requires admin role" do
    sign_in @employee
    post :create, params: { installation_id: "12345" }
    assert_response :forbidden
  end

  # ====== DESTROY ======

  test "#destroy deletes integration for admin" do
    sign_in @admin

    assert_difference("Integration.count", -1) do
      delete :destroy, params: { id: @integration.id }
    end

    assert_response :success
  end

  test "#destroy requires admin role" do
    sign_in @employee
    delete :destroy, params: { id: @integration.id }
    assert_response :forbidden
  end

  test "#destroy cannot delete other company integration" do
    other_integration = create(:integration, company: @other_company, connected_by: @other_admin)
    sign_in @admin

    delete :destroy, params: { id: other_integration.id }
    assert_response :not_found
  end
end
