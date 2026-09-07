# frozen_string_literal: true

require "application_system_test_case"

# E2E critical path: direct file upload, through a headless browser.
#
# This is the only layer that exercises the upload contract for real. The Vitest suite stubs
# @uppy/core and @uppy/aws-s3 inert (docs/testing.md R8), so it never runs the plugin's
# signing protocol, and the request tests drive #presign/#upload by hand rather than through
# Uppy. Here the real @uppy/aws-s3 asks for a signature, PUTs the bytes at the URL it gets
# back, and the frontend parses the cache id out of the resulting uploadURL and promotes it —
# which is the whole chain that a major-version bump of the plugin can break.
class AssetUploadTest < ApplicationSystemTestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, :onboarding_completed, company: @company,
                                  password: AuthHelper::TEST_PASSWORD)
    LoginPage.new.tap(&:load).sign_in(@user.email, AuthHelper::TEST_PASSWORD)
    assert_current_path "/company/projects", wait: 10
  end

  test "an authenticated user uploads a file and it becomes a company asset" do
    assets = CompanyAssetsPage.new
    assets.load

    assets.upload(text_fixture.to_s, folder: "docs")

    assert_text "test_file.txt", wait: 15
    asset = @company.assets.find_by(name: "test_file.txt")
    assert asset, "asset persisted"
    assert_equal "docs", asset.folder
    assert_equal text_fixture.read, asset.latest_version.file.read
  end

  # A .json asset is the case that a raw PUT makes fragile: its Content-Type has a registered
  # ActionDispatch parser, so without Middleware::RawUploadBody the bytes would be parsed as
  # request params — and anything that is not valid JSON would 400 before #upload ever ran.
  test "uploads a json file whose contents are not valid json" do
    path = Rails.root.join("tmp", "broken-#{SecureRandom.hex(4)}.json")
    path.write("{ not valid json,,,")

    assets = CompanyAssetsPage.new
    assets.load
    assets.upload(path.to_s)

    assert_text path.basename.to_s, wait: 15
    asset = @company.assets.find_by(name: path.basename.to_s)
    assert asset, "asset persisted"
    assert_equal "{ not valid json,,,", asset.latest_version.file.read
  ensure
    path&.delete if path&.exist?
  end

  private

  def text_fixture
    Rails.root.join("test", "fixtures", "files", "test_file.txt")
  end
end
