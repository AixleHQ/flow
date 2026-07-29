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

    test "should create company with initial admin user" do
      admin_email = "admin@newcompany.com"
      admin_password = "password123"

      assert_difference("Company.count", 1) do
        assert_difference("User.count", 1) do
          post :create, params: {
            company: attributes_for(:company,
              email_domain: "newcompany.com",
              initial_admin_email: admin_email,
              initial_admin_password: admin_password)
          }
        end
      end

      company = Company.last
      admin_user = User.find_by(email: admin_email)

      assert { admin_user.present? }
      membership = company.company_memberships.find_by(user: admin_user)
      assert { membership.present? }
      assert { membership.admin? }
      assert { membership.active? }
      assert { admin_user.active? }
      assert { admin_user.authenticate(admin_password) }
      assert { admin_user.name.present? } # Name should be generated from email
      assert_redirected_to admin_company_path(company)
    end

    test "should not create company with duplicate email domain" do
      existing_company = create(:company, email_domain: "acme.com")

      assert_no_difference "Company.count" do
        post :create, params: {
          company: attributes_for(:company, email_domain: "acme.com")
        }
      end

      assert_response :unprocessable_entity
    end

    test "should update company email domain" do
      new_domain = "updated-domain.com"

      patch :update, params: {
        id: @company.id,
        company: { email_domain: new_domain }
      }

      @company.reload
      assert { @company.email_domain == new_domain }
      assert_redirected_to admin_company_path(@company)
    end

    test "should update company auto_accept_users setting" do
      patch :update, params: {
        id: @company.id,
        company: { auto_accept_users: true }
      }

      @company.reload
      assert { @company.auto_accept_users == true }
      assert_redirected_to admin_company_path(@company)
    end

    test "should update company branding colors" do
      patch :update, params: {
        id: @company.id,
        company: {
          primary_color: "#FF5733",
          secondary_color: "#33FF57"
        }
      }

      @company.reload
      assert { @company.primary_color == "#FF5733" }
      assert { @company.secondary_color == "#33FF57" }
      assert_redirected_to admin_company_path(@company)
    end

    test "should update company state via state_event" do
      patch :update, params: {
        id: @company.id,
        company: { state_event: "suspend" }
      }

      @company.reload
      assert { @company.suspended? }
      assert_redirected_to admin_company_path(@company)
    end

    test "should destroy company and cascade delete memberships but keep users" do
      company_with_users = create(:company)
      create_list(:user, 3, :employee, company: company_with_users)

      # Users are global identities now — destroying a company removes its
      # memberships, never the user rows themselves.
      assert_difference("Company.count", -1) do
        assert_difference("CompanyMembership.count", -3) do
          assert_no_difference("User.count") do
            delete :destroy, params: { id: company_with_users.id }
          end
        end
      end

      assert_redirected_to admin_companies_path
    end

    test "non-super-admin cannot access companies index" do
      sign_out
      regular_user = create(:user, :with_company)
      sign_in regular_user

      get :index

      assert_response :redirect
    end

    test "non-super-admin cannot create company" do
      sign_out
      admin_user = create(:user, :admin, :with_company)
      sign_in admin_user

      assert_no_difference "Company.count" do
        post :create, params: {
          company: attributes_for(:company)
        }
      end

      assert_response :redirect
    end

    test "non-super-admin cannot update company" do
      sign_out
      admin_user = create(:user, :admin, :with_company)
      sign_in admin_user

      original_name = @company.name

      patch :update, params: {
        id: @company.id,
        company: { name: "Hacked Name" }
      }

      @company.reload
      assert { @company.name == original_name }
      assert_response :redirect
    end

    test "non-super-admin cannot destroy company" do
      sign_out
      admin_user = create(:user, :admin, :with_company)
      sign_in admin_user

      assert_no_difference "Company.count" do
        delete :destroy, params: { id: @company.id }
      end

      assert_response :redirect
    end
  end
end
