# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Direct-upload contract for Api::V1::AssetsController (docs/testing.md §2, request layer).
#
# In production #presign hands back a presigned S3 PUT and the browser never talks to Rails
# again. Locally the same presign points at #upload, which stands in for S3 — so the two
# actions are one round trip and are exercised as one: presign, PUT the bytes at the URL it
# returned, then read the file back out of the cache storage under the id the frontend will
# parse out of that URL.
#
# (This replaces the grandfathered ActionController::TestCase for these actions. The upload
# path only behaves correctly with the full middleware stack in place — Middleware::RawUploadBody
# is what keeps ActionDispatch from parsing a `.json` asset's body — and a controller test
# would run without it.)
class Api::V1::AssetsUploadTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company)
    @user = create(:user, :onboarding_completed, company: @company,
                                                 password: AuthHelper::TEST_PASSWORD)
    sign_in_as @user
  end

  test "presign returns a PUT url whose path carries a fresh cache key" do
    get presign_api_v1_assets_path, params: { filename: "design-spec.pdf", type: "application/pdf" }

    assert_response :success
    assert_equal "PUT", response.parsed_body["method"]
    assert_match %r{/cache/\h{60}\.pdf\z}, response.parsed_body["url"]
  end

  test "presign mints a different key per call" do
    get presign_api_v1_assets_path, params: { filename: "a.txt" }
    first = response.parsed_body["url"]
    get presign_api_v1_assets_path, params: { filename: "a.txt" }

    assert_not_equal first, response.parsed_body["url"]
  end

  test "presign keeps a client filename extension out of the key unless it is a plain suffix" do
    get presign_api_v1_assets_path, params: { filename: "payload.<script>" }

    assert_match %r{/cache/\h{60}\z}, response.parsed_body["url"]
  end

  test "presign handles a filename with no extension" do
    get presign_api_v1_assets_path, params: { filename: "Dockerfile" }

    assert_match %r{/cache/\h{60}\z}, response.parsed_body["url"]
  end

  test "uploading to the presigned url caches the bytes under the id in its path" do
    get presign_api_v1_assets_path, params: { filename: "diagram.png", type: "image/png" }
    url = response.parsed_body["url"]
    bytes = "\x89PNG\r\n\x1a\n not really a png".b

    put url, params: bytes, headers: { "CONTENT_TYPE" => "image/png" }

    assert_response :no_content
    # The frontend derives the cached file's id by splitting the upload URL on "/cache/";
    # this asserts the id it will send back actually addresses the stored object.
    id = url.split("/cache/").last
    assert_equal bytes, Shrine.storages[:cache].open(id).read
  end

  test "stores a json asset whose body is not valid json" do
    get presign_api_v1_assets_path, params: { filename: "broken.json", type: "application/json" }
    url = response.parsed_body["url"]

    put url, params: "{ not valid json,,,", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :no_content
    assert_equal "{ not valid json,,,", Shrine.storages[:cache].open(url.split("/cache/").last).read
  end

  # The production branch, which the local storages never take. Shrine::Storage::S3 is real
  # here (presigned_url is computed offline, no network, no credentials needed beyond the
  # dummies) — what is pinned is the two properties the rest of the flow rests on: the key is
  # reachable in the URL path so the frontend can parse the cache id back out, and `host` is
  # the only signed header, so the Content-Type @uppy/aws-s3 sends cannot invalidate the
  # signature the way a signed :content_type or :content_disposition would.
  test "presign signs an S3 PUT that needs no request headers when cache storage can presign" do
    with_s3_cache_storage do
      get presign_api_v1_assets_path, params: { filename: "design-spec.pdf", type: "application/pdf" }
    end

    assert_response :success
    assert_equal "PUT", response.parsed_body["method"]

    url = URI.parse(response.parsed_body["url"])
    assert_equal "example-assets.s3.amazonaws.com", url.host
    assert_match %r{\A/cache/\h{60}\.pdf\z}, url.path
    assert_equal "host", URI.decode_www_form(url.query).to_h["X-Amz-SignedHeaders"]
  end

  test "upload is not reachable in a non-local environment" do
    Rails.env.stubs(:local?).returns(false)

    put "/api/v1/assets/upload/cache/#{SecureRandom.hex(30)}.txt",
        params: "x", headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :not_found
  end

  # Development stores :cache on disk rather than in memory, and that is a genuinely different
  # write path — Shrine::Storage::FileSystem#upload does IO.copy_stream straight to a file,
  # where Memory does io.read. It is also the storage a developer's own uploads land in, so it
  # gets the same round trip rather than being taken on faith from the Memory run.
  test "uploads through the presigned url into file system storage" do
    Dir.mktmpdir do |dir|
      with_file_system_cache_storage(dir) do
        get presign_api_v1_assets_path, params: { filename: "notes.txt" }
        url = response.parsed_body["url"]

        put url, params: "written to disk", headers: { "CONTENT_TYPE" => "text/plain" }

        assert_response :no_content
        id = url.split("/cache/").last
        assert_equal "written to disk", Shrine.storages[:cache].open(id).read
        assert_path_exists File.join(dir, "cache", id)
      end
    end
  end

  test "rejects an upload key that points outside cache storage" do
    put "/api/v1/assets/upload/store/company/1/assets/evil.txt",
        params: "x", headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :bad_request
  end

  test "rejects an upload key that is not a minted cache id" do
    put "/api/v1/assets/upload/cache/../../etc/passwd",
        params: "x", headers: { "CONTENT_TYPE" => "text/plain" }

    assert_response :bad_request
  end

  private

  def with_file_system_cache_storage(dir)
    require "shrine/storage/file_system"
    with_cache_storage(Shrine::Storage::FileSystem.new(dir, prefix: "cache")) { yield }
  end

  def with_s3_cache_storage
    require "shrine/storage/s3"
    with_cache_storage(Shrine::Storage::S3.new(
      prefix: "cache", bucket: "example-assets", region: "us-east-1",
      access_key_id: "AKIAEXAMPLE", secret_access_key: "secretexample"
    )) { yield }
  end

  def with_cache_storage(storage)
    original = Shrine.storages[:cache]
    Shrine.storages[:cache] = storage
    yield
  ensure
    Shrine.storages[:cache] = original
  end
end
