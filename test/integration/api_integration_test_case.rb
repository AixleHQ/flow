# frozen_string_literal: true

require "test_helper"

# Base for JSON API integration tests (session cookie from the web login form).
class ApiIntegrationTestCase < ActionDispatch::IntegrationTest
  private

  def json_headers
    {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json"
    }
  end

  def api_json_post(path, hash)
    post path, params: hash.to_json, headers: json_headers
  end

  def api_json_patch(path, hash)
    patch path, params: hash.to_json, headers: json_headers
  end

  def api_json_put(path, hash)
    put path, params: hash.to_json, headers: json_headers
  end
end
