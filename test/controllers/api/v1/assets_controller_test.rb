# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AssetsControllerTest < ActionController::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :onboarding_completed, company: @company)
        sign_in @user
      end

      test "presign returns upload instructions" do
        get :presign

        assert_response :success
        json = response.parsed_body
        assert_equal "POST", json["method"]
        assert json["url"].present?
      end

      test "upload returns no content" do
        AssetFileUploader.stubs(:upload_response).returns(
          [
            200,
            {},
            [ { url: "https://example.com/file" }.to_json ]
          ]
        )

        post :upload

        assert_response :no_content
      end
    end
  end
end
