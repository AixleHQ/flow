# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::CollaboratorsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :admin, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @non_collaborator = create(:user, :employee, company: @company)
    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @other_company = create(:company, email_domain: "other.com")
    @other_user = create(:user, :employee, company: @other_company)
  end

  # ====== INDEX Tests ======

  test "#index returns owner and collaborators" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert { json["items"].length == 2 }

    user_ids = json["items"].map { |m| m["id"] }
    assert { user_ids.include?(@owner.id) }
    assert { user_ids.include?(@collaborator.id) }
  end

  test "#index accessible by collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id }

    assert_response :success
  end

  test "#index forbidden for non-collaborator" do
    sign_in @non_collaborator

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  test "#index requires authentication" do
    get :index, params: { project_id: @project.id }

    assert_response :unauthorized
  end

  # ====== CREATE Tests ======

  test "#create adds collaborator" do
    sign_in @owner

    assert_difference "ProjectCollaborator.count", 1 do
      post :create, params: { project_id: @project.id, collaborator: { user_id: @non_collaborator.id } }
    end

    assert_response :created
    json = response.parsed_body
    assert { json["data"]["id"] == @non_collaborator.id }
  end

  test "#create with duplicate user fails" do
    sign_in @owner

    assert_no_difference "ProjectCollaborator.count" do
      post :create, params: { project_id: @project.id, collaborator: { user_id: @collaborator.id } }
    end

    assert_response :unprocessable_entity
  end

  test "#create requires project admin" do
    sign_in @collaborator

    post :create, params: { project_id: @project.id, collaborator: { user_id: @non_collaborator.id } }

    assert_response :forbidden
  end

  test "#create validates same company" do
    sign_in @owner

    assert_no_difference "ProjectCollaborator.count" do
      post :create, params: { project_id: @project.id, collaborator: { user_id: @other_user.id } }
    end

    assert_response :not_found
  end

  test "#create cannot add owner as collaborator" do
    sign_in @owner

    assert_no_difference "ProjectCollaborator.count" do
      post :create, params: { project_id: @project.id, collaborator: { user_id: @owner.id } }
    end

    assert_response :unprocessable_entity
  end

  # ====== DESTROY Tests ======

  test "#destroy removes collaborator by user_id" do
    sign_in @owner

    assert_difference "ProjectCollaborator.count", -1 do
      delete :destroy, params: { project_id: @project.id, id: @collaborator.id }
    end

    assert_response :no_content
  end

  test "#destroy requires project admin" do
    sign_in @collaborator

    delete :destroy, params: { project_id: @project.id, id: @collaborator.id }

    assert_response :forbidden
  end

  test "#destroy prevents admin from removing themselves" do
    sign_in @owner
    # Make owner a collaborator first (edge case)
    other_project = create(:project, company: @company, owner: @collaborator)
    other_project.add_collaborator(@owner)

    sign_in @collaborator

    assert_no_difference "ProjectCollaborator.count" do
      delete :destroy, params: { project_id: other_project.id, id: @collaborator.id }
    end

    assert_response :unprocessable_entity
    json = response.parsed_body
    assert { json["errors"]["base"].include?("Cannot remove yourself from the project") }
  end
end
