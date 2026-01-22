# frozen_string_literal: true

require "test_helper"

module Admin
  class CompaniesControllerTest < Admin::ActionControllerTestCase
    setup do
      @company = create(:company)
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

    test "should create company" do
      assert_difference("Company.count") do
        post :create, params: {
          company: attributes_for(:company)
        }
      end

      assert_redirected_to admin_company_path(Company.last)
    end

    test "should show company" do
      get :show, params: { id: @company.id }
      assert_response :success
    end

    test "should get edit" do
      get :edit, params: { id: @company.id }
      assert_response :success
    end

    test "should update company" do
      patch :update, params: {
        id: @company.id,
        company: {
          name: generate(:name)
        }
      }

      assert_redirected_to admin_company_path(@company)
    end

    test "should destroy company" do
      assert_difference("Company.count", -1) do
        delete :destroy, params: { id: @company.id }
      end

      assert_redirected_to admin_companies_path
    end
  end
end
