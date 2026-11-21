# frozen_string_literal: true

require "test_helper"

# Where the storage cannot sign URLs (Memory here, FileSystem in development), the agent
# container puts a session archive through the app and fetches it back the same way.
class ContainerStorageTest < ActionDispatch::IntegrationTest
  include CheckpointStorageHelper

  setup { @id = "#{SecureRandom.hex(8)}.tar.gz" }

  def path_of(url) = URI(url).request_uri

  def put_url(id = @id, expires_in: 60)
    Uploads::ContainerTransfer.put_url(SessionCheckpointUploader, :cache, id, expires_in: expires_in, host: "web:4000")
  end

  def get_url(id = @id)
    file = SessionCheckpointUploader.uploaded_file(id: id, storage: :cache)
    Uploads::ContainerTransfer.get_url(file, expires_in: 60, host: "web:4000")
  end

  test "an archive put through the app comes back unchanged" do
    put path_of(put_url), params: "archive bytes", headers: { "CONTENT_TYPE" => "application/octet-stream" }
    assert_response :no_content

    get path_of(get_url)
    assert_response :ok
    assert_equal "archive bytes", response.body
  end

  test "a token works for the one object and method it was minted for" do
    put path_of(put_url), params: "archive bytes"

    put path_of(get_url), params: "other bytes"
    assert_response :not_found
    get path_of(put_url)
    assert_response :not_found
    get path_of(get_url("someone-else.tar.gz"))
    assert_response :not_found
    get "/agents/storage", params: { token: "forged" }
    assert_response :not_found
  end

  test "a token expires" do
    url = put_url(expires_in: 60)

    travel 61.seconds do
      put path_of(url), params: "late bytes"
    end
    assert_response :not_found
  end

  test "the app never stands in where the storage signs its own URLs" do
    url = put_url
    use_checkpoint_storage

    put path_of(url), params: "archive bytes"
    assert_response :not_found
  ensure
    restore_checkpoint_storage
  end
end
