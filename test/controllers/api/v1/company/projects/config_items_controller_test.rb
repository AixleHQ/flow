# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::ConfigItemsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @non_member = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @variable = @project.config_items.create!(
      name: "PROJECT_URL",
      value: "https://project.example.com",
      description: "Project URL",
      item_type: :variable
    )

    @secret = @project.config_items.new(
      name: "PROJECT_SECRET",
      description: "Project secret",
      item_type: :secret
    )
    @secret.value = "project_secret_123"
    @secret.save!

    # Company-level items for merge testing
    @company_var = @company.config_items.create!(
      name: "COMPANY_VAR",
      value: "company_value",
      item_type: :variable
    )
    @company_override = @company.config_items.create!(
      name: "PROJECT_URL", # Same name as project item - will be overridden
      value: "https://company.example.com",
      item_type: :variable
    )
  end

  # ====== INDEX Tests (Merged List) ======

  test "#index returns merged list (company + project items)" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    # Returns all items without deduplication:
    # PROJECT_URL (project), PROJECT_SECRET (project), COMPANY_VAR (company), PROJECT_URL (company)
    assert { json["items"].length == 4 }
    names = json["items"].map { |i| i["name"] }
    assert { names.include?("PROJECT_URL") }
    assert { names.include?("PROJECT_SECRET") }
    assert { names.include?("COMPANY_VAR") }
  end

  test "#index returns project item when name exists in both scopes" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    json = response.parsed_body
    project_url_item = json["items"].find { |i| i["name"] == "PROJECT_URL" && i["scope_type"] == "Project" }
    assert { project_url_item["value"] == "https://project.example.com" }
  end

  test "#index returns scope_indicator for each item" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    json = response.parsed_body

    # PROJECT_URL overrides company item
    project_url = json["items"].find { |i| i["name"] == "PROJECT_URL" && i["scope_type"] == "Project" }
    assert { project_url["scope_indicator"] == "overrides_company" }

    # PROJECT_SECRET is project-only
    project_secret = json["items"].find { |i| i["name"] == "PROJECT_SECRET" }
    assert { project_secret["scope_indicator"] == "project" }

    # COMPANY_VAR is company-only (not overridden)
    company_var = json["items"].find { |i| i["name"] == "COMPANY_VAR" }
    assert { company_var["scope_indicator"] == "company" }
  end

  test "#index returns merged list for collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 4 }
  end

  test "#index forbidden for non-member" do
    sign_in @non_member

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index, params: { project_id: @project.id }

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create creates variable for project owner" do
    sign_in @owner

    assert_difference("ConfigItem.count") do
      post :create, params: {
        project_id: @project.id,
        config_item: {
          name: "NEW_PROJECT_VAR",
          value: "new_value",
          description: "New project variable",
          item_type: "variable"
        }
      }
    end

    assert_response :created
    json = response.parsed_body
    item = ConfigItem.find(json["data"]["id"])
    assert { item.name == "NEW_PROJECT_VAR" }
    assert { item.scope == @project }
    assert { item.scope_type == "Project" }
  end

  test "#create allowed for collaborator" do
    sign_in @collaborator

    assert_difference("ConfigItem.count") do
      post :create, params: {
        project_id: @project.id,
        config_item: {
          name: "COLLABORATOR_VAR",
          value: "value",
          item_type: "variable"
        }
      }
    end

    assert_response :created
  end

  test "#create forbidden for non-member" do
    sign_in @non_member

    assert_no_difference("ConfigItem.count") do
      post :create, params: {
        project_id: @project.id,
        config_item: {
          name: "NEW_VAR",
          value: "value",
          item_type: "variable"
        }
      }
    end

    assert_response :forbidden
  end

  # ====== UPDATE Tests ======

  test "#update updates variable for project owner" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @variable.id,
      config_item: {
        value: "updated_url"
      }
    }

    assert_response :success
    @variable.reload
    assert { @variable.value == "updated_url" }
  end

  test "#update allowed for collaborator" do
    sign_in @collaborator

    patch :update, params: {
      project_id: @project.id,
      id: @variable.id,
      config_item: {
        value: "updated_by_collaborator"
      }
    }

    assert_response :success
    @variable.reload
    assert { @variable.value == "updated_by_collaborator" }
  end

  # ====== DESTROY Tests ======

  test "#destroy removes config item for project owner" do
    sign_in @owner

    assert_difference("ConfigItem.count", -1) do
      delete :destroy, params: {
        project_id: @project.id,
        id: @variable.id
      }
    end

    assert_response :no_content
  end

  test "#destroy allowed for collaborator" do
    sign_in @collaborator

    assert_difference("ConfigItem.count", -1) do
      delete :destroy, params: {
        project_id: @project.id,
        id: @variable.id
      }
    end

    assert_response :no_content
  end

  test "#destroy forbidden for non-member" do
    sign_in @non_member

    assert_no_difference("ConfigItem.count") do
      delete :destroy, params: {
        project_id: @project.id,
        id: @variable.id
      }
    end

    assert_response :forbidden
  end
end
