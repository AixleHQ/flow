# frozen_string_literal: true

require "test_helper"

module Admin
  class SessionLogsControllerTest < Admin::ActionControllerTestCase
    setup do
      @user = create(:user, :with_company)
      @project = create(:project, company: @user.company, owner: @user)
      @terminal_session = create(:terminal_session, :with_user, :with_project, user: @user, project: @project)
      @session_log = create(:session_log, terminal_session: @terminal_session)
      @super_admin = create(:user, :super_admin)
      sign_in @super_admin
    end

    test "should get index" do
      get :index
      assert_response :success
    end

    test "should show session_log" do
      get :show, params: { id: @session_log.id }
      assert_response :success
    end

    test "should redirect to file_url when download param present and file_url available" do
      SessionLog.any_instance.stubs(:file_url).returns("https://storage.example.com/log.txt")

      get :show, params: { id: @session_log.id, download: "1" }

      assert_redirected_to "https://storage.example.com/log.txt"
    end

    test "should redirect with flash error when download requested but file_url blank" do
      SessionLog.any_instance.stubs(:file_url).returns(nil)

      get :show, params: { id: @session_log.id, download: "1" }

      assert_redirected_to admin_session_log_path(@session_log)
      assert_equal "File not available", flash[:error]
    end
  end
end
