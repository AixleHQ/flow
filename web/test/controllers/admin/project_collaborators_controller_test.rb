# frozen_string_literal: true

require "test_helper"

module Admin
  class ProjectCollaboratorsControllerTest < Admin::ActionControllerTestCase
    setup do
      @company = create(:company)
      @owner = create(:user, :admin_role, company: @company)
      @collaborator_user = create(:user, :collaborator, company: @company)
      @project = create(:project, company: @company, owner: @owner)
      @project_collaborator = create(:project_collaborator, project: @project, user: @collaborator_user)
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should get new" do
      get :new
      assert_response :success
    end

    test "should create project_collaborator" do
      new_user = create(:user, :collaborator, company: @company)

      assert_difference("ProjectCollaborator.count") do
        post :create, params: {
          project_collaborator: attributes_for(:project_collaborator).merge(
            project_id: @project.id,
            user_id: new_user.id
          )
        }
      end

      assert_redirected_to admin_project_collaborator_path(ProjectCollaborator.last)
    end

    test "should show project_collaborator" do
      get :show, params: { id: @project_collaborator.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @project_collaborator.id }
      assert_response :success
    end

    test "should update project_collaborator" do
      new_user = create(:user, :collaborator, company: @company)

      patch :update, params: {
        id: @project_collaborator.id,
        project_collaborator: {
          user_id: new_user.id
        }
      }

      assert_redirected_to admin_project_collaborator_path(@project_collaborator)
    end

    test "should destroy project_collaborator" do
      assert_difference("ProjectCollaborator.count", -1) do
        delete :destroy, params: { id: @project_collaborator.id }
      end

      assert_redirected_to admin_project_collaborators_path
    end
  end
end
