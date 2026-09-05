# frozen_string_literal: true

require "test_helper"

module Admin
  class NamespaceResourceQuotasControllerTest < Admin::ActionControllerTestCase
    setup do
      @company = create(:company)
      @owner = create(:user, :onboarding_completed, company: @company)
      @project = create(:project, company: @company, owner: @owner)
      @quota = NamespaceResourceQuota.create!(scope: @project, max_pods: 10)
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

    test "should create namespace_resource_quota" do
      new_project = create(:project, company: @company, owner: @owner)

      assert_difference("NamespaceResourceQuota.count") do
        post :create, params: {
          namespace_resource_quota: {
            scope_type: "Project",
            scope_id: new_project.id,
            max_pods: 5,
            cpu_limits: "2",
            memory_limits: "4Gi"
          }
        }
      end

      assert_redirected_to admin_namespace_resource_quota_path(NamespaceResourceQuota.last)
    end

    test "should show namespace_resource_quota" do
      get :show, params: { id: @quota.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @quota.id }
      assert_response :success
    end

    test "should update namespace_resource_quota" do
      patch :update, params: {
        id: @quota.id,
        namespace_resource_quota: { max_pods: 20 }
      }

      assert_redirected_to admin_namespace_resource_quota_path(@quota)
    end

    test "should destroy namespace_resource_quota" do
      assert_difference("NamespaceResourceQuota.count", -1) do
        delete :destroy, params: { id: @quota.id }
      end

      assert_redirected_to admin_namespace_resource_quotas_path
    end
  end
end
