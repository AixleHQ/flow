# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Internal
      class WsAuthControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, company: @company)
          @session = create(:terminal_session, :running, user: @user)

          Rails.logger.stubs(:info)
          Rails.logger.stubs(:warn)
          Rails.logger.stubs(:error)
        end

        # == Route Token Extraction Tests ==

        test "returns bad_request when X-Forwarded-Uri is missing" do
          sign_in @user

          get :show

          assert_response :bad_request
        end

        test "returns bad_request when route_token cannot be extracted" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/invalid/path"

          get :show

          assert_response :bad_request
        end

        test "extracts route_token from /t/{token}/tty/ws path" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :ok
        end

        test "extracts route_token from /t/{token}/fs path" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/fs/files"

          get :show

          assert_response :ok
        end

        # == Session Lookup Tests ==

        test "returns not_found when session does not exist" do
          sign_in @user
          # Use valid hex format that doesn't match any session
          request.headers["X-Forwarded-Uri"] = "/t/abcdef123456789012345678901234567890/tty/ws"

          get :show

          assert_response :not_found
        end

        # == Authentication Tests ==

        test "returns unauthorized when user not authenticated" do
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :unauthorized
        end

        # == Authorization Tests ==

        test "returns forbidden when user does not own session" do
          other_user = create(:user, company: @company)
          sign_in other_user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :forbidden
        end

        # == Session State Tests ==

        test "returns forbidden when session is pending" do
          pending_session = create(:terminal_session, user: @user)
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{pending_session.route_token}/tty/ws"

          get :show

          assert_response :forbidden
        end

        test "returns forbidden when session is collected" do
          collected_session = create(:terminal_session, :collected, user: @user)
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{collected_session.route_token}/tty/ws"

          get :show

          assert_response :forbidden
        end

        test "allows access to started session" do
          started_session = create(:terminal_session, :started, user: @user)
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{started_session.route_token}/tty/ws"

          get :show

          assert_response :ok
        end

        test "allows access to running session" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :ok
        end

        # == Response Headers Tests ==

        test "sets X-User-Id header on success" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :ok
          assert_equal @user.id.to_s, response.headers["X-User-Id"]
        end

        test "sets X-Session-Id header on success" do
          sign_in @user
          request.headers["X-Forwarded-Uri"] = "/t/#{@session.route_token}/tty/ws"

          get :show

          assert_response :ok
          assert_equal @session.id.to_s, response.headers["X-Session-Id"]
        end
      end
    end
  end
end
