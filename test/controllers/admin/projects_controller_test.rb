# frozen_string_literal: true

require "test_helper"

module Admin
  class ProjectsControllerTest < Admin::ActionControllerTestCase
    setup do
      @company = create(:company)
      @owner = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @owner)
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

    test "should create project" do
      assert_difference("Project.count") do
        post :create, params: {
          project: attributes_for(:project).merge(
            company_id: @company.id,
            owner_id: @owner.id
          )
        }
      end

      assert_redirected_to admin_project_path(Project.last)
    end

    test "should show project" do
      get :show, params: { id: @project.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @project.id }
      assert_response :success
    end

    test "should update project" do
      patch :update, params: {
        id: @project.id,
        project: {
          name: generate(:name)
        }
      }

      assert_redirected_to admin_project_path(@project)
    end

    test "should destroy project" do
      assert_difference("Project.count", -1) do
        delete :destroy, params: { id: @project.id }
      end

      assert_redirected_to admin_projects_path
    end
  end
end
