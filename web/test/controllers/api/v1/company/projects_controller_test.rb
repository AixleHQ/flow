# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::ProjectsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
    @employee = create(:user, :employee, company: @company)
    @other_company = create(:company, email_domain: "other.com")
    @other_user = create(:user, :employee, company: @other_company)
  end

  # ====== INDEX Tests ======

  test "#index returns projects for user (owned and collaborated)" do
    sign_in @employee

    # Project owned by employee
    owned_project = create(:project, company: @company, owner: @employee, name: "Owned Project")
    # Project where employee is collaborator
    other_project = create(:project, company: @company, owner: @admin, name: "Collab Project")
    other_project.add_collaborator(@employee)
    # Project employee has no access to
    no_access_project = create(:project, company: @company, owner: @admin, name: "No Access")

    get :index

    assert_response :success
    json = response.parsed_body
    project_ids = json["items"].map { |p| p["id"] }
    assert { project_ids.include?(owned_project.id) }
    assert { project_ids.include?(other_project.id) }
    refute { project_ids.include?(no_access_project.id) }
  end

  test "#index returns only company projects" do
    sign_in @admin

    company_project = create(:project, company: @company, owner: @admin, name: "Company Project")
    other_company_project = create(:project, company: @other_company, owner: @other_user, name: "Other Project")

    get :index

    assert_response :success
    json = response.parsed_body
    project_ids = json["items"].map { |p| p["id"] }
    assert { project_ids.include?(company_project.id) }
    refute { project_ids.include?(other_company_project.id) }
  end

  test "#index admin sees all company projects" do
    sign_in @admin

    # Projects owned by different users
    admin_project = create(:project, company: @company, owner: @admin, name: "Admin Project")
    employee_project = create(:project, company: @company, owner: @employee, name: "Employee Project")

    get :index

    assert_response :success
    json = response.parsed_body
    project_ids = json["items"].map { |p| p["id"] }
    # Admin should see both projects
    assert { project_ids.include?(admin_project.id) }
    assert { project_ids.include?(employee_project.id) }
  end

  test "#index with name filter" do
    sign_in @admin

    create(:project, company: @company, owner: @admin, name: "Alpha Project")
    create(:project, company: @company, owner: @admin, name: "Beta Project")

    get :index, params: { q: { name_cont: "Alpha" } }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 1 }
    assert { json["items"].first["name"] == "Alpha Project" }
  end

  test "#index includes collaborators_count" do
    sign_in @admin

    project = create(:project, company: @company, owner: @admin, name: "Test Project")
    project.add_collaborator(@employee)

    get :index

    assert_response :success
    json = response.parsed_body
    project_data = json["items"].find { |p| p["id"] == project.id }
    assert { project_data["collaborators_count"] == 1 }
  end

  test "#index requires authentication" do
    get :index

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create returns new project" do
    sign_in @admin

    assert_difference "Project.count", 1 do
      post :create, params: { project: { name: "New Project", description: "A test project" } }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "New Project" }
    assert { json["data"]["description"] == "A test project" }
    assert { json["data"]["slug"] == "new-project" }
    assert { json["data"]["state"] == "active" }
    assert { json["data"]["company_id"] == @company.id }
    assert { json["data"]["owner_id"] == @admin.id }
  end

  test "#create allows employees to create projects" do
    sign_in @employee

    assert_difference "Project.count", 1 do
      post :create, params: { project: { name: "Employee Project" } }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["owner_id"] == @employee.id }
  end

  test "#create with duplicate name fails" do
    create(:project, company: @company, name: "Existing Project", owner: @admin)
    sign_in @admin

    assert_no_difference "Project.count" do
      post :create, params: { project: { name: "Existing Project" } }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["name"].present? }
  end

  test "#create requires authentication" do
    post :create, params: { project: { name: "Test Project" } }

    assert_response :unauthorized
  end

  test "#create project is associated with user's company" do
    sign_in @admin

    post :create, params: { project: { name: "Company Project" } }

    assert_response :created
    project = Project.last
    assert { project.company_id == @admin.company_id }
  end

  test "#create user becomes owner" do
    sign_in @employee

    post :create, params: { project: { name: "My Project" } }

    assert_response :created
    project = Project.last
    assert { project.owner_id == @employee.id }
  end

  test "#create generates slug automatically" do
    sign_in @admin

    post :create, params: { project: { name: "My New Project" } }

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["slug"] == "my-new-project" }
  end

  test "#create with minimal params" do
    sign_in @admin

    post :create, params: { project: { name: "Minimal" } }

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["name"] == "Minimal" }
    assert { json["data"]["description"].nil? }
  end
end
