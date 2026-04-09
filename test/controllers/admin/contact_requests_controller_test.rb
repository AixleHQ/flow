# frozen_string_literal: true

require "test_helper"

module Admin
  class ContactRequestsControllerTest < Admin::ActionControllerTestCase
    setup do
      @contact = ContactRequest.create!(first_name: "Jane", last_name: "Doe", email: "jane@example.com")
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should show contact_request" do
      get :show, params: { id: @contact.id }
      assert_response :success
    end

    test "should destroy contact_request" do
      assert_difference("ContactRequest.count", -1) do
        delete :destroy, params: { id: @contact.id }
      end

      assert_redirected_to admin_contact_requests_path
    end
  end
end
