# frozen_string_literal: true

require "test_helper"

module Admin
  class TerminalSessionsControllerTest < Admin::ActionControllerTestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, company: @user.companies.first, owner: @user)
      @session = create(:terminal_session, :with_user, :with_project, user: @user, project: @project)
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should show terminal_session" do
      get :show, params: { id: @session.id }
      assert_response :success
    end
  end
end
