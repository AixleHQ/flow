# frozen_string_literal: true

require "test_helper"

class ApiDocsAuthTest < ActionDispatch::IntegrationTest
  test "with no credentials configured, /api-docs admits nobody instead of failing" do
    Settings.docs.stubs(:login).returns(nil)
    Settings.docs.stubs(:password).returns(nil)

    get "/api-docs", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("user", "") }

    assert_response :unauthorized
  end

  test "the configured pair opens /api-docs, anything else is refused" do
    Settings.docs.stubs(:login).returns("docs-reader")
    Settings.docs.stubs(:password).returns("s3cret-docs")

    get "/api-docs", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("docs-reader", "wrong") }
    assert_response :unauthorized

    get "/api-docs", headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("docs-reader", "s3cret-docs") }
    assert_not_equal 401, response.status
  end
end
