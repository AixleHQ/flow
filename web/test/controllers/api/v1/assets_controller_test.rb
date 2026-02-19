# frozen_string_literal: true

require "test_helper"

class Api::V1::AssetsControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @admin = create(:user, :admin, company: @company)
  end

  # ====== PRESIGN Tests ======

  test "#presign returns presign data for authenticated user" do
    sign_in @admin

    get :presign, params: { filename: "report.pdf", type: "application/pdf" }

    assert_response :success
    json = response.parsed_body
    assert { json["method"] == "POST" }
    assert { json["url"].present? }
    assert { json["fields"].is_a?(Hash) }
    assert { json["fields"]["key"].start_with?("cache/") }
  end

  test "#presign requires authentication" do
    get :presign, params: { filename: "report.pdf", type: "application/pdf" }

    assert_response :unauthorized
  end

  # ====== UPLOAD Tests ======

  test "#upload stores file in cache and returns location" do
    sign_in @admin

    file = fixture_file_upload("test_file.txt", "text/plain")
    post :upload, params: { file: file }

    assert_response :no_content
    assert { (response.headers["Location"] || response.headers[:location]).present? }
  end

  test "#upload requires authentication" do
    file = fixture_file_upload("test_file.txt", "text/plain")
    post :upload, params: { file: file }

    assert_response :unauthorized
  end
end
