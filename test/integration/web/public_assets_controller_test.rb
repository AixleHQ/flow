# frozen_string_literal: true

require "test_helper"

class Web::PublicAssetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @asset = create(:asset, scope: @project, created_by: @user, name: "page.html")
    create(:asset_version, asset: @asset, uploaded_by: @user, content_type: "text/html",
           file: AssetFileUploader.upload(StringIO.new("<b>hi</b>"), :store))
    @token = @asset.share!
  end

  test "show renders the sandboxed viewer for a shared asset" do
    get public_asset_path(token: @token)

    assert_response :success
    assert_includes response.body, "iframe"
    assert_includes response.body, public_asset_raw_path(token: @token)
    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors"
    assert_nil response.headers["X-Frame-Options"]
  end

  test "raw streams the file with sandbox headers" do
    get public_asset_raw_path(token: @token)

    assert_response :success
    assert_equal "<b>hi</b>", response.body
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Content-Type"], "text/html"
  end

  test "show 404s for an unknown token" do
    get public_asset_path(token: "nope")
    assert_response :not_found
  end

  test "raw 404s for an unknown token" do
    get public_asset_raw_path(token: "nope")
    assert_response :not_found
  end

  test "404s once the asset is unshared" do
    @asset.unshare!

    get public_asset_path(token: @token)
    assert_response :not_found
  end
end
