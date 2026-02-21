# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Internal
      class UsageStatisticsControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :admin, company: @company)
          @project = create(:project, company: @company, owner: @user)
          @session = create(:terminal_session, :running, :with_user, :with_project, user: @user, project: @project)
        end

        test "#create returns ok when service persists" do
          result = UsageStatisticsService::Result.new(status: :ok)
          UsageStatisticsService.stubs(:process).returns(result)

          post :create, body: '{"resourceMetrics":[]}', as: :json

          assert_response :success
          json = response.parsed_body
          assert_equal "ok", json["status"]
        end

        test "#create returns accepted when service returns accepted" do
          result = UsageStatisticsService::Result.new(status: :accepted)
          UsageStatisticsService.stubs(:process).returns(result)

          post :create, body: "{}", as: :json

          assert_response :accepted
        end

        test "#create returns bad_request when service returns bad_request" do
          result = UsageStatisticsService::Result.new(status: :bad_request, error: "Invalid JSON")
          UsageStatisticsService.stubs(:process).returns(result)

          post :create, body: "invalid", as: :json

          assert_response :bad_request
          json = response.parsed_body
          assert_equal "Invalid JSON", json["error"]
        end

        test "#create returns not_found when service returns not_found" do
          result = UsageStatisticsService::Result.new(status: :not_found, error: "Session not found")
          UsageStatisticsService.stubs(:process).returns(result)

          post :create, body: '{"resourceMetrics":[{}]}', as: :json

          assert_response :not_found
        end

        test "#create returns internal_server_error when service returns error" do
          result = UsageStatisticsService::Result.new(status: :error, error: "Failed to persist usage")
          UsageStatisticsService.stubs(:process).returns(result)

          post :create, body: "{}", as: :json

          assert_response :internal_server_error
          json = response.parsed_body
          assert json["error"].present?
        end

        test "#create passes raw body to service" do
          body = '{"test": true}'
          UsageStatisticsService.expects(:process).with(body).returns(
            UsageStatisticsService::Result.new(status: :ok)
          )

          post :create, body: body, as: :json

          assert_response :success
        end
      end
    end
  end
end
