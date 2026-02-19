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
    assert { json["items"].first["repos_count"] == 0 }
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
    assert { names == ["acme-corp"] }
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
      post :create, params: { installation_id: "99999" }
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
      post :create, params: { installation_id: "bad-id" }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["status"] == "error" }
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
